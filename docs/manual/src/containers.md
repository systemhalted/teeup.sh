# Containers

teeup runs containers with [Colima](https://github.com/abiosoft/colima), a small Linux virtual machine, and the ordinary Docker command-line client. There is no Docker Desktop. All of it is one lazy capability, `colima`.

| Command | What it does |
|---|---|
| `docker ...` | The first time, offers to install Colima, then runs your command. |
| `teeup install colima` | Installs it straight away. |
| `colima-start`, `colima-stop` | Start or stop the virtual machine. These aliases exist once Colima is installed. |
| `colima status` | Whether the virtual machine is running. |
| `teeup remove colima` | Stops the virtual machine, then uninstalls Colima, Docker and Compose. |

## What gets installed

| Package | Homebrew | MacPorts |
|---|---|---|
| Colima | `colima` | `colima` |
| Docker CLI | `docker` | `docker` |
| Compose | `docker-compose` | `docker-compose-plugin` |

On Homebrew, teeup links the Compose plugin into `~/.docker/cli-plugins`, so `docker compose` works as a subcommand. If you set `DOCKER_CONFIG`, the link goes under that directory instead.

## The first run

Configuring Colima starts its virtual machine, so the first `docker ps` takes a while: teeup installs the three packages, runs `colima start`, and then runs `docker ps`. Colima makes itself Docker's default context when it starts, so nothing else needs setting.

```sh
docker ps          # installs, starts Colima, then lists containers
docker run --rm hello-world
```

<!-- SCREENSHOT: The first `docker ps` on a fresh Mac: the Install now? prompt, the colima start output, and the empty container list. -->

## After a restart

The virtual machine does not start at login. After a reboot, start it before using Docker:

```sh
colima start
```

`teeup configure colima` also starts it when it is stopped. `teeup update` does not configure lazy capabilities, so it never starts the virtual machine behind your back.

## Removing it

`teeup remove colima` stops a running virtual machine first. If `colima stop` fails, teeup refuses to go on, because uninstalling Colima under a running machine would orphan it. Stop it by hand, then run the removal again. On Homebrew it also removes the Compose plugin link it made.
