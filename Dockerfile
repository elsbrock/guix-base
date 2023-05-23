# syntax=docker/dockerfile:1.3-labs
FROM debian@sha256:432f545c6ba13b79e2681f4cc4858788b0ab099fc1cca799cc0fae4687c69070 AS debug_hook

ENV DEBIAN_FRONTEND=noninteractive

# install the base requirements, and proot, and set locale
# the guix binary is extracted into the ~/guix folder which
# contains /var, /etc and the /gnu store
RUN <<INSTALL
set -e
apt-get update && apt-get install -y wget locales gpg xz-utils less netbase bash procps git
rm -rf /var/lib/apt/lists/*
localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
useradd -ms /bin/bash guix
wget -O /usr/local/bin/proot https://proot.gitlab.io/proot/bin/proot
chmod +x /usr/local/bin/proot
INSTALL

# set environment variables
# renovate: datasource=github-tags depName=guix-mirror/guix
ENV GUIX_VERSION v1.3.0
ENV LANG en_US.utf8

# these guix profile variables are only valid within a proot
ENV GUIX_PROFILE /home/guix/.config/guix/current
ENV GUIX_LOCPATH /var/guix/profiles/per-user/root/guix-profile/lib/locale
ENV _GUIX_PROFILE $GUIX_PROFILE
ENV PATH $PATH:$GUIX_PROFILE/bin

# we bootstrap guix using a regular user via proot
USER guix
WORKDIR /home/guix

# bootstrap guix
RUN <<BOOTSTRAP
#!/bin/bash
set -e
# fetch binaries containing guix-daemon and other guix commands
echo wget -q https://ftp.gnu.org/gnu/guix/guix-binary-${GUIX_VERSION/v/}.x86_64-linux.tar.xz
wget -q https://ftp.gnu.org/gnu/guix/guix-binary-${GUIX_VERSION/v/}.x86_64-linux.tar.xz
wget -q https://ftp.gnu.org/gnu/guix/guix-binary-${GUIX_VERSION/v/}.x86_64-linux.tar.xz.sig
wget -q "https://sv.gnu.org/people/viewgpg.php?user_id=127547" -qO - | gpg --import -
gpg --verify guix-binary-${GUIX_VERSION/v/}.x86_64-linux.tar.xz.sig
# unpack to ~/guix
mkdir guix && tar --warning=no-timestamp -C guix -xf guix-binary-${GUIX_VERSION/v/}.x86_64-linux.tar.xz && rm guix-binary-${GUIX_VERSION/v/}.x86_64-linux.tar.xz
# create additional dirs required to proot later
mkdir -p .config/guix guix/etc
# mark installation as current
ln -sf ~/guix/var/guix/profiles/per-user/root/current-guix ~/.config/guix/current
# use github mirror instead of savannah
COMMIT=$(git ls-remote -q git://github.com/guix-mirror/guix ${GUIX_VERSION}^{} | awk '{print $1}')
cat <<EOF > ~/.config/guix/channels.scm
(map (lambda (chan)
        (if (guix-channel? chan)
            (channel
            (inherit chan)
            (url "https://github.com/guix-mirror/guix.git")
            (commit "$COMMIT"))
            chan))
    %default-channels)
EOF
BOOTSTRAP

FROM debug_hook

# setup guix
# 1) start guix-daemon in the background
# 2) authorize build server and update the system
RUN <<SETUP
#!/bin/bash
# start guix daemon in the background
exec proot -b guix/gnu:/gnu -b guix/var:/var -b /proc -b /dev -b guix/etc:/etc/guix sh <<'SCRIPT'
    . $GUIX_PROFILE/etc/profile
    guix-daemon --disable-chroot &
    pid=$!
    guix archive --authorize < $GUIX_PROFILE/share/guix/ci.guix.gnu.org.pub && guix pull
    kill $pid && wait || true
SCRIPT
SETUP

# store the entrypoint using root
ENTRYPOINT ["proot", "-b guix/gnu:/gnu", "-b guix/var:/var", "-b /proc", "-b /dev", "-b guix/etc:/etc/guix", "/usr/bin/entrypoint.sh"]
USER root

# entrypoint: 
# 1) start guix-daemon in the background
# 2) pack the requested package
COPY <<"ENTRY" /usr/bin/entrypoint.sh
#!/bin/bash
set -o pipefail
exec 6>&1 1>&2
. $GUIX_PROFILE/etc/profile
guix-daemon --disable-chroot &
pid=$!
guix pack --format=docker --root=pack.tgz $@
test -f pack.tgz && cat pack.tgz >&6
# we ignore the exit code of the daemon here since the
# previous commands succeeded
kill $pid && wait || true
ENTRY

RUN chmod +x /usr/bin/entrypoint.sh

USER guix
WORKDIR /home/guix
