# (Unofficial) Guix Base Docker Image

**An  *unofficial* Docker image with GNU Guix installed**

This Docker image provides a non-root GNU Guix installation that can be used to execute arbitrary (but probably not all) `guix` commands.

The original motivation for this image was to identify a way to build reproducible Docker images. If you think it through, building reproducible images is kind of hard, because only few package maintainers publish Docker images, much less reproducible ones – instead, you typically use a general purpose Docker base image (such as `debian`) to install a binary or compile your package from source. This leads to a lot of externalities introduced and typically means that no exact image reproduction can be built locally.

Recently I happened to learn about and became interested in modern package managers such as Nix, or GNU Guix. I learned that you can use Guix to produce perfectly reproducible Docker images, and I wanted to be able to use it for [elsbrock/tor-node](https://github.com/elsbrock/tor-node). So, this is what I came up with.

As soon as the container is started, `guix-daemon` is started in the background. All processes are started under the `guix` user, ie. no `--privileged` container or generally `root` is required.

## Usage

By default (without entrypoint override) the container will execute `guix build && guix pack` of the provided package name. The name must be a valid Guix package name (see [Packages](https://guix.gnu.org/en/packages/)).

```sh
docker run --rm -it ghcr.io/elsbrock/guix-base tor
```

## About GNU Guix

<center>

![guix logo](https://guix.gnu.org/static/base/img/Guix.png)

<small>_Copyright © 2015 Luis Felipe López Acevedo_</small>

</center>

<blockquote>
The GNU Guix package and system manager is a free software project developed by volunteers around the world under the umbrella of the GNU Project.

Guix System is an advanced distribution of the GNU operating system. It uses the Linux-libre kernel, and support for the Hurd is being worked on. As a GNU distribution, it is committed to respecting and enhancing the freedom of its users. As such, it adheres to the GNU Free System Distribution Guidelines.

GNU Guix provides state-of-the-art package management features such as transactional upgrades and roll-backs, reproducible build environments, unprivileged package management, and per-user profiles. It uses low-level mechanisms from the Nix package manager, but packages are defined as native Guile modules, using extensions to the Scheme language—which makes it nicely hackable.

Guix takes that a step further by additionally supporting stateless, reproducible operating system configurations. This time the whole system is hackable in Scheme, from the initial RAM disk to the initialization system, and to the system services.

_https://guix.gnu.org/en/about/_
</blockquote>

## Resources

* [GNU Guix Homepage](http://guix.gnu.org)
* [proot Homepage](https://proot-me.github.io/)
