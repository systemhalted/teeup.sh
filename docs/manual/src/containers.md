# Containers

teeup runs containers with [Colima](https://github.com/abiosoft/colima) and the Docker command-line client.
`colima` is a lazy capability.

| Command | What it does |
|---|---|
| `docker ...` | The first time, teeup asks you to install Colima. Then teeup runs your command. |
| `teeup install colima` | Installs Colima immediately. |
| `colima-start`, `colima-stop` | Starts or stops the virtual machine. These aliases are available when you install Colima. |
| `colima status` | Shows the status of the virtual machine. |
| `teeup remove colima` | Stops the virtual machine. Then teeup uninstalls Colima, Docker, and Compose. |

## What gets installed

| Package | Homebrew | MacPorts |
|---|---|---|
| Colima | `colima` | `colima` |
| Docker CLI | `docker` | `docker` |
| Compose | `docker-compose` | `docker-compose-plugin` |

On Homebrew, teeup links the Compose plugin into `~/.docker/cli-plugins`.
As a result, `docker compose` runs as a subcommand.
If you set `DOCKER_CONFIG`, teeup puts the link under that directory instead.

## The first run

When teeup configures Colima, teeup starts the virtual machine.
The first `docker ps` requires time.
It installs the packages, starts the virtual machine, and lists the containers.
Colima sets itself as the default Docker context.

```sh
docker ps          # installs, starts Colima, then lists containers
docker run --rm hello-world
```

<!-- SCREENSHOT: The first `docker ps` on a fresh Mac: the Install now? prompt, the colima start output, and the empty container list. -->

## After a restart

The virtual machine does not start at login.
After a restart, start the virtual machine before you use Docker:

```sh
colima start
```

If the virtual machine does not run, `teeup configure colima` starts it.
`teeup update` does not configure lazy capabilities.
`teeup update` also does not start the virtual machine.

## Removing it

`teeup remove colima` stops an active virtual machine first.
If `colima stop` fails, teeup stops.

Do not uninstall Colima while the virtual machine runs.
The virtual machine continues to run, and Colima cannot stop it.
Stop the virtual machine manually.
Then run `teeup remove colima` again.

On Homebrew, teeup also removes the Compose plugin link that teeup made.
