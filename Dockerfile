# syntax=docker/dockerfile:1.3-labs
FROM debian

ENV DEBIAN_FRONTEND=noninteractive

# install the base requirements, and proot, and set locale
# the guix binary is extracted into the ~/guix folder which
# contains /var, /etc and the /gnu store
RUN <<INSTALL
set -e
apt-get update && apt-get install -y wget locales gpg xz-utils less netbase bash
rm -rf /var/lib/apt/lists/*
localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
useradd -ms /bin/bash guix
wget -O /usr/local/bin/proot https://proot.gitlab.io/proot/bin/proot
chmod +x /usr/local/bin/proot
INSTALL

# set environment variables
ENV GUIX_VERSION v1.3.0
ENV LANG en_US.utf8

# these guix profile variables are only valid within a proot
ENV GUIX_PROFILE "/home/guix/.config/guix/current"
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
mkdir guix && tar --warning=no-timestamp -C guix -xf guix-binary-${GUIX_VERSION/v/}.x86_64-linux.tar.xz
# create additional dirs required to proot later
mkdir -p .config/guix guix/etc
# mark installation as current
ln -sf ~/guix/var/guix/profiles/per-user/root/current-guix ~/.config/guix/current
# use github mirror instead of savannah
cat <<EOF > ~/.config/guix/channels.scm
(map (lambda (chan)
        (if (guix-channel? chan)
            (channel
            (inherit chan)
            (url "https://github.com/guix-mirror/guix.git")
            (commit "a0178d34f582b50e9bdbb0403943129ae5b560ff"))
            chan))
    %default-channels)
EOF
BOOTSTRAP

# setup guix
# 1) start guix-daemon in the background
# 2) authorize build server and update the system
RUN <<SETUP
#!/bin/bash
set -e
# start guix daemon in the background
proot -b guix/gnu:/gnu -b guix/var:/var -b /proc -b /dev -b guix/etc:/etc/guix sh <<'SCRIPT' &
    . $GUIX_PROFILE/etc/profile
    PATH=$PATH:$GUIX_PROFILE/bin
    guix-daemon --disable-chroot
SCRIPT
# store pid of guix-daemon to wait for it
pid=$!
# update guix using substitutes
proot -b guix/gnu:/gnu -b guix/var:/var -b /proc -b /dev -b guix/etc:/etc/guix sh <<SCRIPT
    . $GUIX_PROFILE/etc/profile
    PATH=$PATH:$GUIX_PROFILE/bin
    guix archive --authorize < $GUIX_PROFILE/share/guix/ci.guix.gnu.org.pub && guix pull
    echo guix pull done
SCRIPT
kill $pid
wait $pid
SETUP

# store the entrypoint using root
USER root

# entrypoint: 
# 1) start guix-daemon in the background
# 2) build and export the requested package
COPY <<"RUN" /usr/bin/entrypoint.sh
#!/bin/bash
set -e
proot -b guix/gnu:/gnu -b guix/var:/var -b /proc -b /dev -b guix/etc:/etc/guix sh <<'SCRIPT' &
    . $GUIX_PROFILE/etc/profile
    PATH=$PATH:$GUIX_PROFILE/bin
    guix-daemon --disable-chroot
SCRIPT
# store pid of guix-daemon to wait for it
pid=$!
proot -b guix/gnu:/gnu -b guix/var:/var -b /proc -b /dev -b guix/etc:/etc/guix sh <<SCRIPT
    . $GUIX_PROFILE/etc/profile
    PATH=$PATH:$GUIX_PROFILE/bin
    guix build $@ && guix pack --format=docker --entry-point=bin/tor --root=pack.tgz $@
SCRIPT
kill $pid
wait $pid
RUN

RUN chmod +x /usr/bin/entrypoint.sh

USER guix
WORKDIR /home/guix
ENTRYPOINT ["/usr/bin/entrypoint.sh"]