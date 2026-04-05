# dory

[![Gem Version](https://badge.fury.io/rb/dory.svg)](https://badge.fury.io/rb/dory) [![Build Status](https://travis-ci.org/FreedomBen/dory.svg?branch=master)](https://travis-ci.org/FreedomBen/dory) [![Code Climate](https://codeclimate.com/github/FreedomBen/dory/badges/gpa.svg)](https://codeclimate.com/github/FreedomBen/dory) [![Test Coverage](https://codeclimate.com/github/FreedomBen/dory/badges/coverage.svg)](https://codeclimate.com/github/FreedomBen/dory/coverage) [![Dependency Status](https://dependencyci.com/github/FreedomBen/dory/badge)](https://dependencyci.com/github/FreedomBen/dory)

[Dory](https://github.com/FreedomBen/dory) lets you forget about IP addresses and port numbers
while you are developing your application.  Through the magic of local DNS and
a reverse proxy, you can access your app at the domain of your choosing.  For example,
http://myapp.docker or http://this-is-a-really-long-name.but-its-cool-cause-i-like-it

Now with support for Docker for Mac and even [dinghy! (more info on using with dinghy below)](#usage-with-dinghy)

Dory wraps [codekitchen/dinghy-http-proxy](https://github.com/codekitchen/dinghy-http-proxy)
and makes it easily available for use outside of [dinghy](https://github.com/codekitchen/dinghy).
This way you can work comfortably side by side with your colleagues who run dinghy on macOS.

Specifically, dory will:

* Fire up the nginx proxy in a daemonized docker container for you
* Configure and start a local dnsmasq to forward DNS queries for
your local domain to the nginx proxy
* Configure your local DNS resolver to point to the local dnsmasq

## Installation

A package for .deb and .rpm is planned as well as a systemd service.
If you'd like to help out with any of that, let me know!

### [Homebrew](https://brew.sh) (recommended on macOS)

```bash
brew install dory
```

### Ruby gem (recommended on Linux)

**NOTE:** Dory requires ruby version 2.2 or greater to be installed on your system already.

If you use multiple versions, your system ruby is too old or you just prefer not to install gems into your system ruby, I recommend installing the ruby version with [ruby-install](https://github.com/postmodern/ruby-install) and then managing it with [chruby](https://github.com/postmodern/chruby).

```bash
gem install dory
```

### Arch Linux (hosted on the [quarry repository](https://wiki.archlinux.org/index.php/Unofficial_user_repositories#quarry))

```bash
pacman -S ruby-dory
```

## Quick Start

In most cases, the default configuration will be all you need.  You literally
just [set the VIRTUAL_HOST environment variable in your container](#making-your-containers-accessible-by-name-dns),
[install dory](#installation) and then run:

    dory up

If you want to fine-tune, generate a config file with:

    dory config-file

and edit away at `~/.dory.yml`

## Usage

Dory has a small selection of commands that are hopefully intuitive.
To customize and fine-tune dory's behavior, it can be configured with a yaml config file.

### Commands
```
Commands:
  dory attach          # Attach to the output of a docker service container
  dory config-file     # Write a default config file
  dory down            # Stop all dory services
  dory help [COMMAND]  # Describe available commands or one specific command
  dory ip              # Grab the IPv4 address of a running dory service
  dory pull            # Pull down the docker images that dory uses
  dory restart         # Stop and restart all dory services
  dory status          # Report status of the dory services
  dory up              # Bring up dory services (nginx-proxy, dnsmasq, resolv)
  dory upgrade         # Upgrade dory to the latest version
  dory version         # Check current installed version of dory

Options:
  v, [--verbose], [--no-verbose]
```

### Config file

Dory will start looking for a config file in your current working directory, and will recurse up to `/` until it finds one.  If dory does not find a config file, it will use the default settings.

You can bootstrap your config file with the default settings using `dory config-file`.  This
file will be placed by default at `~/.dory.yml`, but again you can move it to a preferred place.  This allows you to have project-specific dory configs if you so desire by putting the config at
`<your-project>/.dory.yml`:

```yaml
---
dory:
  # Be careful if you change the settings of some of
  # these services.  They may not talk to each other
  # if you change IP Addresses.
  # For example, resolv expects a nameserver listening at
  # the specified address.  dnsmasq normally does this,
  # but if you disable dnsmasq, it
  # will make your system look for a name server that
  # doesn't exist.
  dnsmasq:
    enabled: true
    autostart: false       # true to set the container to restart unless stopped (e.g. after reboot)
    domains:               # array of domains that will be resolved to the specified address
      - domain: docker     # you can set '#' for a wildcard
        address: 127.0.0.1 # return for queries against the domain
    container_name: dory_dnsmasq
    port: 53  # port to listen for dns requests on.  must be 53 on linux. can be anything that's open on macos
    # kill_others: kill processes bound to the port we need (see previous setting 'port')
    #   Possible values:
    #     ask (prompt about killing each time. User can accept/reject)
    #     yes|true (go ahead and kill without asking)
    #     no|false (don't kill, and don't even ask)
    kill_others: ask
    service_start_delay: 5  # seconds to wait after restarting systemd services
  nginx_proxy:
    enabled: true
    autostart: false   # true to set the container to restart unless stopped (e.g. after reboot)
    container_name: dory_dinghy_http_proxy
    https_enabled: true
    ssl_certs_dir: ''  # leave as empty string to use default certs
    port: 80           # port 80 is default for http
    tls_port: 443      # port 443 is default for https

  resolv:
    enabled: true
    nameserver: 127.0.0.1
    port: 53  # port where the nameserver listens. On linux it must be 53
  
  aliases:
    enabled: true 
    autostart: false  # true to make the aliases persist across restarts
    # addresses:
    #   To allow containers to talk to each other by their names,
    #   set dnsmasq.domains[].address to a private IP and add it here
    #   (Supported on MacOS only)
    #   - <ip>
```

#### Upgrading existing config file

If you run the `dory config-file` command and have an existing config file,
dory will offer you the option of upgrading.  This will preserve your settings
and migrate you to the latest format.  You can skip the prompt by passing the
`--upgrade` flag

```
dory config-file --upgrade
```

```
Usage:
  dory config-file

Options:
  u, [--upgrade], [--no-upgrade]
  f, [--force]

Description:
  Writes a dory config file to /home/ben/.dory.yml containing the default
  settings. This can then be configured as preferred.
```

## Making your containers accessible by name (DNS)

To make your container(s) accessible through a domain, all you have to do is set
a `VIRTUAL_HOST` environment variable in your container.  That's it!  (Well, and you have
to start dory with `dory up`)

The proxy will by default use the first port exposed by your container as the HTTP port to proxy to.
This can be overridden by setting the `VIRTUAL_PORT` environment variable on the container to the desired HTTP port.

You will also need to set `VIRTUAL_PORT` if your server binds to something other than 80
inside its container (e.g. `VIRTUAL_PORT: 3000`).  This will tell the nginx proxy which
port to forward traffic to in your container.  When accessing the server from outside
of docker, you will still hit port 80 (such as with your web browser).

If your back-end container uses HTTPS, then set `VIRTUAL_PROTO: https` to tell the nginx
proxy to use https instead of the default http.

Many people do this in their `docker-compose.yml` file:

```yaml
version: '2'
services:
  web:
    build: .
    depends_on:
      - db
      - redis
    environment:
      VIRTUAL_HOST: myapp.docker
  redis:
    image: redis
    environment:
      VIRTUAL_HOST: redis.docker
      VIRTUAL_PORT: 6379
  db:
    image: postgres
    environment:
      VIRTUAL_HOST: postgres.docker
      VIRTUAL_PORT: 5432
```

In the example above, you can hit the web container from the host machine with `http://myapp.docker`,
and the redis container with `tcp://redis.docker`.  This does *not* affect any links on the internal docker network.

You could also just run a docker container with the environment variable like this:

```
docker run -e VIRTUAL_HOST=myapp.docker  ...
```

## Usage with dinghy

If you are using dinghy, but want to use dory to manage the proxy instead of dinghy's built-in stuff,
this is now possible! (the use case for this that we ran into was multiple domain support.  For example,
the dev wanted to have some containers accessible at `something.docker`).  To accomplish this,
you need to disable dinghy's proxy stuff (otherwise dinghy and dory will stomp on each other's resolv files):

In your [`~/.dinghy/preferences.yml`](https://github.com/codekitchen/dinghy#preferences)
file, disable the proxy:

```yaml
:preferences:
  :proxy_disabled: true
  ...
```

In your dory config file (which can be at `<your-project>/.dory.yml` or anywhere else in parent directories,
`~/.dory.yml` being the default) (hint: if it doesn't exist, [generate it with `dory config-file`](#config-file)),
set your dnsmasq domains and their addresses to `dinghy`, as well as the resolv nameserver.  Here is
an example (with unrelated parts removed for ease of reading):

```yaml
---
dory:
  dnsmasq:
    domains:
      - domain: docker
        address: dinghy # instead of the default 127.0.0.1
    ...
  resolv:
    nameserver: dinghy # instead of the default 127.0.0.1
```

If the dinghy vm gets rebooted for some reason, or otherwise changes IP addresses,
you may need to restart dory to pickup the changes:

```
dory restart
```

## Root privilege requirement

To configure the local resolver, dory needs to edit the `/etc/resolv.conf`. Therefore
you may be prompted for your `sudo` password during `dory up/restart/down`.
If you do not want to enter your password every time you can extend the
`sudoers` config as follows:

```
sudo visudo -f /etc/sudoers.d/dory-edit-resolv-conf
```

To allow passwordless execution only for a single user (replace `my-user` accordingly):

```
Cmnd_Alias DORY_EDIT_RESOLVCONF = /usr/bin/tee /etc/resolv.conf
my-user ALL=(root) NOPASSWD: DORY_EDIT_RESOLVCONF
```

To allow passwordless execution for all users in group `sudo` (you can list the affected users with `awk -F':' '/sudo/{print $4}' /etc/group`):
```
Cmnd_Alias DORY_EDIT_RESOLVCONF = /usr/bin/tee /etc/resolv.conf
%sudo ALL=(root) NOPASSWD: DORY_EDIT_RESOLVCONF
```

On OS X you probably need to change `%sudo` to `%admin`:
```
Cmnd_Alias DORY_EDIT_RESOLVCONF = /usr/bin/tee /etc/resolv.conf
%admin ALL=(root) NOPASSWD: DORY_EDIT_RESOLVCONF
```

*Note: Changes are only applied after closing the file.*


## Troubleshooting

*Help the dnsmasq container is having issues starting!*

Make sure you aren't already running a dnsmasq service (or some other service) on port 53.
Because the Linux resolv file doesn't have support for port numbers, we have to run
on host port 53.  To make matters fun, some distros (such as those shipping with
[NetworkManager](https://wiki.archlinux.org/index.php/NetworkManager)) will
run a dnsmasq on 53 to perform local DNS caching.  This is nice, but it will
conflict with Dory's dnsmasq container.  You will probably want to disable it.

If using Network Manager, try commenting out `dns=dnsmasq`
in `/etc/NetworkManager/NetworkManager.conf`.  Then restart
NetworkManager:  `sudo service network-manager restart` or
`sudo systemctl restart NetworkManager`

If you're using Network Manager/DNSMasqd to do NAT and/or share internet with the computer 
you are installing dory on, stop. You'd need to configure dory's built in DNSmasq to do 
the same, which is not trivial, out of scope, and probably more than you're bargaining for.

If you are on Mac, you can choose which port to bind the dnsmasq container to.  In your
dory config file, adjust the setting under `dory -> dnsmasq -> port`.  You probably want
to make `dory -> resolv -> port` match.  The default value on Mac is 19323.

As of version 0.5.0, dory is a little smarter at handling this problem for you.
dory will identify if you have systemd services running that will race for the port
and cause issues.  It will offer to put those services down temporarily and then put
them back up when finished.  You can configure this behavior in the [config file](#config-file)
to achieve minimal annoyance (since you'll likely be prompted every time by default).

## Is this dinghy for Linux?

No. Well, maybe sort of, but not really.  [Dinghy](https://github.com/codekitchen/dinghy)
has a lot of responsibilities on OS X, most of which are not necessary on Linux since
docker runs natively.  Something it does that can benefit linux users however, is the
setup and management of an [nginx reverse HTTP proxy](https://www.nginx.com/resources/admin-guide/reverse-proxy/).
For this reason, dory exists to provide this reverse proxy on Linux, along with
accompanying dnsmasq and resolv services.
Using full dinghy on Linux for local development doesn't really make sense to me,
but using a reverse proxy does.  Furthermore, if you work with other devs who run
Dinghy on OS X, you will have to massage your [docker-compose](https://docs.docker.com/compose/)
files to avoid conflicting.  By using  [dory](https://github.com/FreedomBen/dory),
you can safely use the same `VIRTUAL_HOST` setup without conflict.  And because
dory uses [dinghy-http-proxy](https://github.com/codekitchen/dinghy-http-proxy)
under the hood, you will be as compatible as possible.

## Are there any reasons to run full dinghy on Linux?

Generally speaking, IMHO, no.  The native experience is superior.  However, for
some reason maybe you'd prefer to not have docker on your local machine?
Maybe you'd rather run it in a VM?  If that describes you, then maybe you want full dinghy.

I am intrigued at the possibilities of using dinghy on Linux to drive a
cloud-based docker engine.  For that, stay tuned.

## Why didn't you just fork dinghy?

That was actually my first approach, and I considered it quite a bit.  As I
went through the process in my head tho, and reviewed the dinghy source code,
I decided that it was just too heavy to really fit the need I had.  I love being
able to run docker natively, and I revere
[the Arch Way](https://wiki.archlinux.org/index.php/Arch_Linux#Principles).  Dinghy just
seemed like too big of a hammer for this problem (the problem being that I work
on Linux, but my colleagues use OS X/Dinghy for docker development).

## What if I'm developing on a cloud server?

You do this too!?  Well fine hacker, it's your lucky day because dory has you
covered.  You can run the nginx proxy on the cloud server and the dnsmasq/resolver
locally.  Here's how:

* Install dory on both client and server:
```
gem install dory
```
* Gen a base config file:
```
dory config-file
```
* On the local machine, disable the nginx-proxy, and set the dnsmasq address to that of your cloud server:
```yaml
  dnsmasq:
    enabled: true
    domain: docker      # domain that will be listened for
    address: <cloud-server-ip>  # address returned for queries against domain
    container_name: dory_dnsmasq
  nginx_proxy:
    enabled: false
    container_name: dory_dinghy_http_proxy
```
* On the server, disable resolv and dnsmasq:
```yaml
  dnsmasq:
    enabled: false
    domain: docker      # domain that will be listened for
    address: 127.0.0.1  # address returned for queries against domain
    container_name: dory_dnsmasq
  resolv:
    enabled: false
    nameserver: 127.0.0.1
```
* Profit!

## Contributing

Want to contribute?  Cool!  Fork it, push it, request it.  Please try to write tests for any functionality you add.

## Development Quick Start

1.  If you want to send a pull request with your changes, then fork the repo
1.  Clone it:  `git clone https://github.com/FreedomBen/dory.git` or if you forked in step 1, use the URL for your fork
1.  Make your changes
1.  Build the gem locally:  `gem build dory.gemspec`
1.  Now you can run your locally built version of the gem like normal:  `dory <somecommand>`
1.  Rinse and repeat.  For easy cleaning and reinstalling, I recommend using this command, which you might want to alias:  `rm *.gem; gem clean dory; yes | gem uninstall dory; gem build dory.gemspec && gem install dory*.gem`
1.  Run the specs locally (note that I've attempted to make the specs interfere with the running system as minimally as possible, but some things are difficult to avoid.  For example, if you have something running on port 53, the specs will kill it.  Also, you will need to enter password for sudo):  `bundle exec rspec spec/`
1.  Specific specs can be run with:  `bundle exec rspec spec/some/file.rb`

## Built on:

* [jwilder/nginx-proxy](https://github.com/jwilder/nginx-proxy) (Indirectly but worthy of mention)
* [codekitchen/dinghy-http-proxy](https://github.com/codekitchen/dinghy-http-proxy)
* [freedomben/dory-http-proxy](https://github.com/freedomben/dory-http-proxy)
* [andyshinn/dnsmasq](https://hub.docker.com/r/andyshinn/dnsmasq/)
* [freedomben/dory-dnsmasq](https://github.com/FreedomBen/dory-dnsmasq)
* [erikhuda/thor](https://github.com/erikhuda/thor)
