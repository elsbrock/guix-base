# syntax=docker/dockerfile:1.3-labs
FROM debian

ENV DEBIAN_FRONTEND=noninteractive

RUN <<INSTALL
apt-get update && apt-get install -y wget locales gpg xz-utils less netbase
rm -rf /var/lib/apt/lists/*
localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
useradd -ms /bin/bash guix
wget -O /usr/local/bin/proot https://proot.gitlab.io/proot/bin/proot
chmod +x /usr/local/bin/proot
INSTALL

ENV LANG en_US.utf8
WORKDIR /home/guix
USER guix
RUN <<"INSTALL"
wget -q https://ftp.gnu.org/gnu/guix/guix-binary-1.3.0.x86_64-linux.tar.xz
wget -q https://ftp.gnu.org/gnu/guix/guix-binary-1.3.0.x86_64-linux.tar.xz.sig
wget -q "https://sv.gnu.org/people/viewgpg.php?user_id=127547" -qO - | gpg --import -
gpg --verify guix-binary-1.3.0.x86_64-linux.tar.xz.sig
mkdir guix && tar --warning=no-timestamp -C guix -xf guix-binary-1.3.0.x86_64-linux.tar.xz
mkdir -p .config/guix
ln -sf ~/guix/var/guix/profiles/per-user/root/current-guix ~/.config/guix/current
proot -b guix/gnu:/gnu -b guix/var:/var ls -lhaLR .config/guix/current/etc/profile
INSTALL

ENV GUIX_PROFILE="/home/guix/.config/guix/current"

COPY <<"EOF" /usr/bin/entrypoint.sh
#!/bin/bash
set -e
echo "starting guix-daemon"
proot -b guix/gnu:/gnu -b guix/var:/var -b /proc -b /dev sh <<'SCRIPT' &
    . $GUIX_PROFILE/etc/profile
    PATH=$PATH:$GUIX_PROFILE/bin
    guix-daemon --disable-chroot --debug
SCRIPT
pid=$!
echo "running guix build"
proot -b guix/gnu:/gnu -b guix/var:/var -b /proc -b /dev sh <<SCRIPT
    . $GUIX_PROFILE/etc/profile
    PATH=$PATH:$GUIX_PROFILE/bin
    guix build $@ && guix pack --format=docker --entry-point=bin/tor --root=pack.tgz $@
SCRIPT
kill $pid
wait $pid
EOF

USER root
RUN chmod +x /usr/bin/entrypoint.sh

USER guix
WORKDIR /home/guix
ENTRYPOINT ["/usr/bin/entrypoint.sh"]