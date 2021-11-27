# syntax=docker/dockerfile:1.3-labs
FROM debian

ENV DEBIAN_FRONTEND=noninteractive

RUN <<INSTALL
apt-get update && apt-get install -y wget locales gpg xz-utils less netbase
rm -rf /var/lib/apt/lists/*
localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
useradd -ms /bin/bash guix
INSTALL

ENV LANG en_US.utf8
ENV GUIX_BINARY_FILE_NAME=guix-binary-nightly.x86_64-linux.tar.xz

USER root
RUN <<"INSTALL"
wget -nv https://git.savannah.gnu.org/cgit/guix.git/plain/etc/guix-install.sh -O guix-install.sh
wget -nv https://ci.guix.gnu.org/search/latest/archive?query=spec:tarball+status:success+system:x86_64-linux+guix-binary.tar.xz -O guix-binary-nightly.x86_64-linux.tar.xz
wget "https://sv.gnu.org/people/viewgpg.php?user_id=127547" -qO - | gpg --import -
wget "https://sv.gnu.org/people/viewgpg.php?user_id=15145" -qO - | gpg --import -
bash -c 'yes | bash guix-install.sh'
guix archive --generate-key
cat <<EOF >/channels.scm
(map (lambda (chan)
        (if (guix-channel? chan)
            (channel
            (inherit chan)
            (url "https://github.com/guix-mirror/guix.git"))
            chan))
    %default-channels)
EOF
wget https://proot.gitlab.io/proot/bin/proot
chmod +x ./proot && mv ./proot /usr/local/bin
chmod a+rx /root/.config/guix/current/bin/guix-daemon
INSTALL

COPY <<"EOF" /usr/bin/entrypoint.sh
#!/bin/bash
set -e
mkdir gnu-store
proot -b gnu-store:/gnu
/root/.config/guix/current/bin/guix-daemon --disable-chroot &
pid=$!
guix build $@ && guix pack --format=docker --entry-point=bin/tor --root=pack.tgz $@
kill $pid
wait $pid
EOF

RUN chmod +x /usr/bin/entrypoint.sh

USER guix
WORKDIR /home/guix
ENTRYPOINT ["/usr/bin/entrypoint.sh"]