# syntax=docker/dockerfile:1.3-labs
FROM debian

ENV DEBIAN_FRONTEND=noninteractive

RUN <<INSTALL
set -e
apt-get update && apt-get install -y wget locales gpg xz-utils less netbase bash
rm -rf /var/lib/apt/lists/*
localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
useradd -ms /bin/bash guix
wget -O /usr/local/bin/proot https://proot.gitlab.io/proot/bin/proot
chmod +x /usr/local/bin/proot
INSTALL

ENV GUIX_VERSION v1.3.0
ENV LANG en_US.utf8
ENV GUIX_PROFILE="/home/guix/.config/guix/current"
ENV PATH $PATH:$GUIX_PROFILE/bin

WORKDIR /home/guix
USER guix
RUN <<INSTALL
#!/bin/bash
set -e
echo wget -q https://ftp.gnu.org/gnu/guix/guix-binary-${GUIX_VERSION/v/}.x86_64-linux.tar.xz
wget -q https://ftp.gnu.org/gnu/guix/guix-binary-${GUIX_VERSION/v/}.x86_64-linux.tar.xz
wget -q https://ftp.gnu.org/gnu/guix/guix-binary-${GUIX_VERSION/v/}.x86_64-linux.tar.xz.sig
wget -q "https://sv.gnu.org/people/viewgpg.php?user_id=127547" -qO - | gpg --import -
gpg --verify guix-binary-${GUIX_VERSION/v/}.x86_64-linux.tar.xz.sig
mkdir guix && tar --warning=no-timestamp -C guix -xf guix-binary-${GUIX_VERSION/v/}.x86_64-linux.tar.xz
mkdir -p .config/guix
ln -sf ~/guix/var/guix/profiles/per-user/root/current-guix ~/.config/guix/current
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
INSTALL

RUN <<"EOF"
#!/bin/bash
set -e
proot -b guix/gnu:/gnu -b guix/var:/var -b /proc -b /dev sh <<'SCRIPT' &
    . $GUIX_PROFILE/etc/profile
    PATH=$PATH:$GUIX_PROFILE/bin
    guix-daemon --disable-chroot --substitute-urls='https://ci.guix.gnu.org'
SCRIPT
pid=$!
proot -b guix/gnu:/gnu -b guix/var:/var sh <<SCRIPT
    . $GUIX_PROFILE/etc/profile
    PATH=$PATH:$GUIX_PROFILE/bin
    guix pull --fallback
    guix archive --authorize < guix/share/guix/ci.guix.gnu.org.pub
SCRIPT
kill $pid
wait $pid
EOF

USER root

COPY <<EOF /usr/bin/entrypoint.sh
#!/bin/bash
set -e
proot -b guix/gnu:/gnu -b guix/var:/var -b /proc -b /dev sh <<'SCRIPT' &
    . $GUIX_PROFILE/etc/profile
    PATH=$PATH:$GUIX_PROFILE/bin
    guix-daemon --disable-chroot --substitute-urls='https://ci.guix.gnu.org'
SCRIPT
pid=$!
proot -b guix/gnu:/gnu -b guix/var:/var sh <<SCRIPT
    . $GUIX_PROFILE/etc/profile
    PATH=$PATH:$GUIX_PROFILE/bin
    guix build $@ && guix pack --format=docker --entry-point=bin/tor --root=pack.tgz $@
SCRIPT
kill $pid
wait $pid
EOF

RUN chmod +x /usr/bin/entrypoint.sh

USER guix
WORKDIR /home/guix
ENTRYPOINT ["/usr/bin/entrypoint.sh"]