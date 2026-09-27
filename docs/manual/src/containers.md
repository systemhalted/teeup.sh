# Containers

teeup runs containers with [Colima](https://github.com/abiosoft/colima) and the Docker command-line client. `colima` is a lazy capability.

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

Configuring Colima starts its virtual machine. The first `docker ps` takes time to install the packages, start the virtual machine, and list containers. Colima sets itself as the default Docker context.

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

`teeup configure colima` starts the virtual machine if it is stopped. `teeup update` does not configure lazy capabilities and does not start the virtual machine.

## Removing it

`teeup remove colima` stops a running virtual machine first. If `colima stop` fails, teeup stops. Uninstalling Colima with a running machine leaves it orphaned. Stop it by hand, then run the removal again. On Homebrew it also removes the Compose plugin link it made.
