# Ansible Architecture and Design

## Ansible Configuration Priorities

Ansible looks for its configuration in several places, applying them in a strict order of precedence. The first match
wins — so a setting found higher up the list will always override the same setting found lower down.

1. `ANSIBLE_CONFIG` environment variable (if set, points to a specific file)
2. `ansible.cfg` in the current working directory
3. `~/.ansible.cfg` in the user's home directory
4. `/etc/ansible/ansible.cfg` (the global system-wide default)

This means you can have a global baseline config at `/etc/ansible/ansible.cfg` and override specific settings
per-project by dropping an `ansible.cfg` in your project directory — which is exactly what the Docker lab does. The
bind-mounted `ansible.cfg` in `/ansible/` takes effect because that's the working directory inside the control node
container.

You can always check which config file Ansible is actually using by running:

```bash
ansible --version
```

This prints the active config file path alongside the Ansible version, which is useful for debugging unexpected
behaviour.

### Common Configuration Sections

`ansible.cfg` is divided into sections. The most commonly used ones are:

**`[defaults]`** — General settings that apply to all operations, such as the default inventory path, remote user,
number of parallel forks, and output formatting.

**`[ssh_connection]`** — Controls how Ansible makes SSH connections, including pipelining, timeout values, and any extra
SSH arguments to pass through.

**`[privilege_escalation]`** — Configures `become` behaviour globally, such as the default escalation method (`sudo`)
and whether to prompt for a password.

---

## How Ansible Manages Nodes

### Node Discovery

Ansible has no daemon, no background process, and no built-in service discovery. It doesn't scan your network looking
for hosts or maintain an ongoing connection to anything. Instead, it relies entirely on the inventory to know what hosts
exist — when you run a playbook or an ad-hoc command, Ansible reads the inventory, builds a list of target hosts, and
then reaches out to each one fresh.

This is an important mental model to have: Ansible is fundamentally **pull-your-inventory, push-your-tasks**. Nothing
happens until you initiate it.

### Communication Over SSH

For Linux and Unix hosts, Ansible communicates exclusively over SSH. No agent is installed, no port is opened, and
nothing is left running on the managed node after a task completes. The entire interaction for a single task looks like
this:

```
Control Node                          Managed Node
     │                                     │
     │──── SSH connection ────────────────>│
     │──── Upload module (Python) ────────>│
     │──── Execute module ────────────────>│
     │<─── Capture result ─────────────────│
     │──── Remove temporary files ────────>│
     │──── Close connection ───────────────│
     │                                     │
```

With **pipelining enabled** (as in the lab's `ansible.cfg`), the upload and execute steps are combined into a single SSH
connection rather than two, which significantly reduces overhead when running playbooks against many hosts.

For Windows hosts, Ansible uses **WinRM** (Windows Remote Management) instead of SSH, though more recent versions also
support SSH on Windows.

### Fact Gathering

Before running any tasks, Ansible by default runs a special built-in module called `setup` against every target host.
This collects detailed information about the host — called **facts** — and makes them available as variables throughout
the playbook:

```yaml
# Facts are automatically available after gather_facts: true (the default)
- name: Print OS information
  debug:
    msg: "{{ ansible_distribution }} {{ ansible_distribution_version }}"

- name: Print available memory
  debug:
    msg: "{{ ansible_memfree_mb }}MB free"

- name: Print all network interfaces
  debug:
    msg: "{{ ansible_interfaces }}"
```

Some commonly used built-in facts:

| Fact                           | Description                            |
|--------------------------------|----------------------------------------|
| `ansible_hostname`             | Short hostname of the managed node     |
| `ansible_fqdn`                 | Fully qualified domain name            |
| `ansible_os_family`            | OS family (Debian, RedHat, etc.)       |
| `ansible_distribution`         | Specific distro (Ubuntu, CentOS, etc.) |
| `ansible_architecture`         | CPU architecture (x86_64, arm64, etc.) |
| `ansible_default_ipv4.address` | Primary IP address                     |
| `ansible_memtotal_mb`          | Total RAM in MB                        |
| `ansible_processor_vcpus`      | Number of vCPUs                        |

Fact gathering adds a small overhead per host. For large inventories or simple tasks that don't need system information,
you can disable it:

```yaml
- name: Quick task with no facts needed
  hosts: all
  gather_facts: false

  tasks:
    - name: Ping
      ping:
```

You can also define your own **custom facts** by placing scripts or JSON files in `/etc/ansible/facts.d/` on a managed
node. These are then available under the `ansible_local` namespace:

```yaml
- name: Read a custom fact
  debug:
    msg: "{{ ansible_local.myapp.version }}"
```

### Parallelism and Forks

Ansible doesn't run tasks against hosts one at a time by default. It processes hosts in parallel batches, controlled by
the `forks` setting in `ansible.cfg` (default is 5):

```ini
[defaults]
forks = 10
```

This means with `forks = 10`, Ansible will run the current task against up to 10 hosts simultaneously before moving to
the next task. The task order is always preserved — Ansible finishes a task across all hosts in the current batch before
moving on.

You can also control this at the play level using `serial`, which is useful for rolling deployments where you want to
update a few hosts at a time rather than all at once:

```yaml
- name: Rolling deployment
  hosts: webservers
  serial: 2        # Update 2 hosts at a time

  tasks:
    - name: Deploy app
      copy:
        src: app.tar.gz
        dest: /opt/app.tar.gz
```

### Connection Variables

The way Ansible connects to each host is controlled by a set of special variables that can be set in inventory,
`group_vars`, or `host_vars`:

| Variable                       | Description                                                        |
|--------------------------------|--------------------------------------------------------------------|
| `ansible_host`                 | The actual IP or hostname to connect to (overrides inventory name) |
| `ansible_port`                 | SSH port (default: 22)                                             |
| `ansible_user`                 | The user to SSH in as                                              |
| `ansible_ssh_private_key_file` | Path to the private key to use                                     |
| `ansible_become`               | Whether to escalate privileges                                     |
| `ansible_become_method`        | How to escalate (`sudo`, `su`, etc.)                               |
| `ansible_become_user`          | The user to escalate to (default: root)                            |
| `ansible_connection`           | Connection type (`ssh`, `local`, `winrm`, etc.)                    |

A practical example — if your inventory name is a logical label but the actual address is different:

```ini
[webservers]
web1 ansible_host=192.168.1.10 ansible_port=2222
web2 ansible_host=192.168.1.11
```

### The `local` Connection

Setting `ansible_connection=local` tells Ansible to run tasks directly on the control node itself rather than over SSH.
This is useful for provisioning steps that interact with APIs or local tools rather than remote hosts:

```yaml
- name: Run locally
  hosts: localhost
  connection: local

  tasks:
    - name: Create an AWS S3 bucket
      s3_bucket:
        name: my-bucket
        state: present
```

---

## Ansible Inventories

An inventory is Ansible's source of truth for what hosts exist and how they are organised. Every Ansible command needs
an inventory to know what to act on.

### Static Inventories

The simplest form — a file you write and maintain manually. Supports INI and YAML formats.

**INI format** (what the lab uses):

```ini
[webservers]
web1
web2

[databases]
db1

[all:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3
```

**YAML format** (equivalent):

```yaml
all:
  children:
    webservers:
      hosts:
        web1:
        web2:
    databases:
      hosts:
        db1:
  vars:
    ansible_user: root
    ansible_python_interpreter: /usr/bin/python3
```

### Dynamic Inventories

For cloud environments where hosts come and go, maintaining a static file isn't practical. Dynamic inventories are
scripts or plugins that query an external source (AWS, GCP, Azure, VMware, etc.) and return host information at runtime.

```bash
# Example: using the AWS EC2 dynamic inventory plugin
ansible-playbook site.yml -i aws_ec2.yml
```

Most major cloud providers have a maintained inventory plugin available through Ansible Galaxy.

### Groups and Nesting

Groups are the primary way to organise hosts. A host can belong to multiple groups, and groups can be nested inside
other groups using the `:children` suffix.

```ini
[webservers]
web1
web2

[databases]
db1

[production:children]
webservers
databases
```

Here `production` is a parent group that contains all hosts from both `webservers` and `databases`. Running a playbook
against `production` would target all three hosts.

Ansible also has two built-in groups that always exist:

- `all` — every host in the inventory
- `ungrouped` — hosts not assigned to any explicit group

### Variables in Inventory

Variables can be attached to individual hosts or entire groups directly in the inventory file. For anything beyond a few
simple variables, the recommended approach is to use separate variable files in `group_vars/` and `host_vars/`
directories alongside your inventory:

```
inventory/
├── hosts
├── group_vars/
│   ├── all.yml          # applies to every host
│   ├── webservers.yml   # applies to the webservers group
│   └── databases.yml    # applies to the databases group
└── host_vars/
    └── web1.yml         # applies only to web1
```

This keeps your inventory file clean and makes variables easy to find and manage.

### Useful Inventory Commands

```bash
# List all hosts in the inventory
ansible all --list-hosts

# List hosts in a specific group
ansible webservers --list-hosts

# Show all variables Ansible has for a specific host
ansible-inventory --host web1

# Display the full inventory as JSON
ansible-inventory --list
```

---

## Ansible Modules

Modules are the units of work that Ansible executes on managed nodes. Every task in a playbook calls exactly one module.
Ansible ships with hundreds of built-in modules covering a huge range of functionality, and thousands more are available
through Ansible Galaxy collections.

### How Modules Work

When Ansible runs a task, it takes the module's Python code, bundles it with any arguments you've provided, copies it to
the managed node over SSH, executes it, captures the result, and then removes the temporary file. This is why managed
nodes only need Python installed — the module code is pushed to them at runtime rather than pre-installed.

### Module Categories

**Package management**

```yaml
- name: Install nginx
  apt:
    name: nginx
    state: present

- name: Install multiple packages
  yum:
    name:
      - git
      - curl
      - htop
    state: present
```

**File operations**

```yaml
- name: Create a directory
  file:
    path: /etc/myapp
    state: directory
    mode: '0755'

- name: Copy a file
  copy:
    src: files/myapp.conf
    dest: /etc/myapp/myapp.conf
    owner: root
    mode: '0644'

- name: Render a template
  template:
    src: templates/nginx.conf.j2
    dest: /etc/nginx/nginx.conf
```

**Service management**

```yaml
- name: Ensure nginx is started and enabled
  service:
    name: nginx
    state: started
    enabled: true
```

**Command execution**

```yaml
# Use 'command' for simple commands with no shell features needed
- name: Run a command
  command: /usr/bin/myapp --init

# Use 'shell' when you need pipes, redirects, or shell builtins
- name: Run a shell command
  shell: cat /etc/os-release | grep VERSION
```

**User management**

```yaml
- name: Create a user
  user:
    name: deploy
    shell: /bin/bash
    groups: sudo
    append: true
```

### Idempotency

Most built-in modules are idempotent — they check the current state of the system before making changes and only act if
the desired state differs from the actual state. The `apt` module won't reinstall a package that's already present. The
`file` module won't recreate a directory that already exists with the right permissions.

The `command` and `shell` modules are a notable exception — Ansible has no way to know if a shell command has already
been run, so they always execute. You can make them conditional using `creates` or `removes` arguments, or by
registering the result and using `when`:

```yaml
- name: Run only if file doesn't exist
  command: /usr/bin/myapp --init
  args:
    creates: /etc/myapp/initialized
```

### Checking What a Module Does

```bash
# Show documentation for any module
ansible-doc apt
ansible-doc service
ansible-doc file

# List all available modules
ansible-doc -l
```

### Return Values

Every module returns a result dictionary that you can capture and use in subsequent tasks using `register`:

```yaml
- name: Check if a file exists
  stat:
    path: /etc/myapp/config.yml
  register: config_file

- name: Print whether the file exists
  debug:
    msg: "Config exists: {{ config_file.stat.exists }}"

- name: Only run if config is missing
  command: /usr/bin/myapp --generate-config
  when: not config_file.stat.exists
```

This pattern — register a result, inspect it, conditionally act on it — is one of the most commonly used patterns in
real-world playbooks.