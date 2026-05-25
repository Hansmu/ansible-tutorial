# Ansible Playbooks

## What is a Playbook?

A playbook is a YAML file that describes automation tasks — what should happen, on which hosts, and in what order. It is
the primary way you interact with Ansible for anything beyond a quick one-off ad-hoc command.

Where an ad-hoc command runs a single module once, a playbook can orchestrate dozens of tasks across multiple groups of
hosts, handle errors, make decisions based on conditions, and be run repeatedly with consistent results.

---

## Structure of a Playbook

A playbook is made up of one or more **plays**. Each play targets a group of hosts and defines a list of tasks to run
against them. Multiple plays in the same file allow you to do different things to different groups of hosts in sequence.

```yaml
---
- name: Configure web servers        # Play 1
  hosts: webservers
  become: true

  tasks:
    - name: Install nginx
      apt:
        name: nginx
        state: present

    - name: Start nginx
      service:
        name: nginx
        state: started

- name: Configure database servers   # Play 2
  hosts: databases
  become: true

  tasks:
    - name: Install postgresql
      apt:
        name: postgresql
        state: present
```

The `---` at the top is a YAML convention marking the start of a document. It's optional but considered good practice.

---

## Play Options

Each play supports a number of options that control how it runs:

```yaml
- name: Example play
  hosts: webservers        # Which hosts or groups to target
  become: true             # Escalate privileges (sudo)
  become_user: root        # Which user to escalate to
  gather_facts: true       # Collect host facts before running tasks (default: true)
  vars: # Variables scoped to this play
    http_port: 80
  environment: # Environment variables set on the managed node
    APP_ENV: production
  serial: 2                # How many hosts to act on at a time
  any_errors_fatal: true   # Stop all hosts if any host fails
  max_fail_percentage: 20  # Allow up to 20% of hosts to fail before aborting
```

---

## Tasks

Tasks are the individual steps within a play. Each task calls exactly one module and gives it a name for readability in
output.

```yaml
tasks:
  - name: Install nginx
    apt:
      name: nginx
      state: present
```

### Task Options

Tasks support several options beyond the module call itself:

**`become`** — Override privilege escalation at the task level:

```yaml
- name: Run as a specific user
  command: /opt/myapp/deploy.sh
  become: true
  become_user: deploy
```

**`when`** — Only run the task if a condition is true:

```yaml
- name: Install apache on Debian systems only
  apt:
    name: apache2
    state: present
  when: ansible_os_family == "Debian"
```

**`loop`** — Repeat a task over a list of items:

```yaml
- name: Install multiple packages
  apt:
    name: "{{ item }}"
    state: present
  loop:
    - nginx
    - git
    - curl
```

**`register`** — Capture the task's return value for use in later tasks:

```yaml
- name: Check if config exists
  stat:
    path: /etc/myapp/config.yml
  register: config_file

- name: Create config if missing
  copy:
    src: files/config.yml
    dest: /etc/myapp/config.yml
  when: not config_file.stat.exists
```

**`notify`** — Trigger a handler when the task makes a change:

```yaml
- name: Update nginx config
  template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
  notify: Restart nginx
```

**`ignore_errors`** — Continue even if the task fails:

```yaml
- name: Try to stop a service that might not exist
  service:
    name: oldapp
    state: stopped
  ignore_errors: true
```

**`tags`** — Label tasks so you can run a subset of a playbook:

```yaml
- name: Install nginx
  apt:
    name: nginx
    state: present
  tags:
    - install
    - nginx
```

```bash
# Only run tasks tagged with 'nginx'
ansible-playbook site.yml --tags nginx

# Skip tasks tagged with 'install'
ansible-playbook site.yml --skip-tags install
```

**`delegate_to`** — Run a task on a different host than the current target:

```yaml
- name: Remove host from load balancer before deploying
  command: /usr/bin/lb-remove {{ inventory_hostname }}
  delegate_to: loadbalancer.example.com
```

**`run_once`** — Execute a task on only one host in the targeted group, even if the play targets many:

```yaml
- name: Run database migration once
  command: /opt/myapp/migrate.sh
  run_once: true
```

This is useful for tasks like database migrations or cache warm-ups that should only happen once per deployment, not
once per host.

**`timeout`** — Set a per-task timeout in seconds (Ansible 2.10+):

```yaml
- name: Run a potentially slow script
  command: /usr/bin/slow-report.sh
  timeout: 60
```

If the task exceeds the timeout, Ansible marks it as failed.

---

## Handlers

Handlers are special tasks that only run when triggered by a `notify` directive, and only if the notifying task actually
made a change. They always run at the end of the play, regardless of where in the task list the `notify` appeared.

```yaml
tasks:
  - name: Update nginx config
    template:
      src: nginx.conf.j2
      dest: /etc/nginx/nginx.conf
    notify: Restart nginx

  - name: Update nginx SSL cert
    copy:
      src: files/cert.pem
      dest: /etc/nginx/cert.pem
    notify: Restart nginx

handlers:
  - name: Restart nginx
    service:
      name: nginx
      state: restarted
```

Even if both tasks notify the same handler, the handler only runs once. This prevents unnecessary service restarts when
multiple config files change in the same play.

### Flushing Handlers Mid-Play

By default, handlers run only at the end of a play. If you need them to run earlier — for example, before a later task
depends on the restarted service — use `meta: flush_handlers`:

```yaml
tasks:
  - name: Update app config
    template:
      src: app.conf.j2
      dest: /etc/myapp/app.conf
    notify: Restart myapp

  - name: Flush handlers now so myapp is running for the next task
    meta: flush_handlers

  - name: Run a health check against the restarted app
    uri:
      url: http://localhost:8080/health
      status_code: 200
```

### Listening to Multiple Notifiers

A handler can declare a `listen` topic, allowing multiple tasks to trigger it with a shared label rather than the
handler's exact name:

```yaml
tasks:
  - name: Update nginx main config
    template:
      src: nginx.conf.j2
      dest: /etc/nginx/nginx.conf
    notify: nginx config changed

  - name: Update nginx site config
    template:
      src: site.conf.j2
      dest: /etc/nginx/sites-available/mysite.conf
    notify: nginx config changed

handlers:
  - name: Restart nginx
    listen: nginx config changed
    service:
      name: nginx
      state: restarted
```

---

## Variables in Playbooks

Variables can be defined at multiple levels within a playbook. The order of precedence from lowest to highest is:

1. Role defaults
2. Inventory variables
3. `group_vars` files
4. `host_vars` files
5. Play `vars`
6. Task `vars`
7. `set_fact` / `register`
8. Extra vars passed on the command line (`-e`)

### Defining Variables in a Play

```yaml
- name: Deploy application
  hosts: webservers
  vars:
    app_version: "2.1.0"
    deploy_dir: /opt/myapp

  tasks:
    - name: Create deploy directory
      file:
        path: "{{ deploy_dir }}"
        state: directory
```

### Defining Variables in a File

```yaml
- name: Deploy application
  hosts: webservers
  vars_files:
    - vars/common.yml
    - vars/production.yml
```

### Setting Variables at Runtime

```yaml
- name: Set a fact for use later in the play
  set_fact:
    app_url: "https://{{ ansible_default_ipv4.address }}:{{ http_port }}"
```

### Passing Variables on the Command Line

```bash
ansible-playbook site.yml -e "app_version=2.1.0 deploy_dir=/opt/myapp"
```

Command line variables override everything else — useful for one-off overrides without editing files.

### Prompting for Variables

You can prompt the operator for variable values at runtime using `vars_prompt`. This is useful for sensitive data like
passwords that shouldn't be stored in files:

```yaml
- name: Deploy application
  hosts: webservers
  vars_prompt:
    - name: db_password
      prompt: "Enter the database password"
      private: true       # Input is hidden (like a password field)

    - name: app_version
      prompt: "Which version to deploy?"
      default: "2.1.0"   # Press Enter to accept default
      private: false
```

`private: true` suppresses echoing input to the terminal. `default` provides a fallback if the operator just presses
Enter.

---

## Conditionals

The `when` directive accepts any valid Jinja2 expression. Multiple conditions can be combined:

```yaml
# AND — both must be true
- name: Install on Debian with enough memory
  apt:
    name: myapp
    state: present
  when:
    - ansible_os_family == "Debian"
    - ansible_memtotal_mb >= 512

# OR — either must be true
- name: Install on Debian or Ubuntu
  apt:
    name: myapp
    state: present
  when: ansible_distribution == "Debian" or ansible_distribution == "Ubuntu"

# Based on a registered result
- name: Run only if previous task changed something
  command: /usr/bin/myapp --reload
  when: config_file.changed
```

---

## Loops

Loops allow a task to repeat over a list without duplicating task definitions.

```yaml
# Simple list
- name: Create multiple directories
  file:
    path: "{{ item }}"
    state: directory
  loop:
    - /opt/myapp
    - /opt/myapp/logs
    - /opt/myapp/config

# List of dictionaries
- name: Create users
  user:
    name: "{{ item.name }}"
    groups: "{{ item.groups }}"
    shell: /bin/bash
  loop:
    - { name: alice, groups: sudo }
    - { name: bob, groups: developers }

# Loop over a registered result
- name: Show all installed packages
  debug:
    msg: "{{ item }}"
  loop: "{{ ansible_facts.packages.keys() | list }}"
```

### Loop Control

`loop_control` lets you customise loop behaviour — most importantly, the label shown in output and an optional pause
between iterations:

```yaml
- name: Deploy to each environment
  command: /usr/bin/deploy.sh {{ item.env }}
  loop:
    - { env: staging, url: staging.example.com }
    - { env: production, url: example.com }
  loop_control:
    label: "{{ item.env }}"   # Show 'staging' / 'production' instead of the full dict
    pause: 5                  # Wait 5 seconds between iterations
```

### `with_` — The Legacy Loop Syntax

Before `loop` was introduced in Ansible 2.5, looping was done using `with_*` keywords. You will encounter these
frequently in older playbooks, roles on Ansible Galaxy, and blog posts — so it is important to recognise them even
though `loop` is now preferred.

Each `with_*` keyword is a shorthand for a specific lookup plugin. The most common ones:

**`with_items`** — the direct equivalent of `loop` with a flat list:

```yaml
# Old syntax
- name: Install packages
  apt:
    name: "{{ item }}"
    state: present
  with_items:
    - nginx
    - git
    - curl

# Modern equivalent
- name: Install packages
  apt:
    name: "{{ item }}"
    state: present
  loop:
    - nginx
    - git
    - curl
```

**`with_dict`** — iterate over a dictionary's key/value pairs, available as `item.key` and `item.value`:

```yaml
- name: Create config entries
  lineinfile:
    path: /etc/myapp/config.ini
    line: "{{ item.key }}={{ item.value }}"
  with_dict:
    db_host: localhost
    db_port: "5432"
    db_name: myapp

# Modern equivalent using dict2items filter
- name: Create config entries
  lineinfile:
    path: /etc/myapp/config.ini
    line: "{{ item.key }}={{ item.value }}"
  loop: "{{ config | dict2items }}"
  vars:
    config:
      db_host: localhost
      db_port: "5432"
      db_name: myapp
```

**`with_fileglob`** — iterate over files matching a glob pattern on the control node:

```yaml
- name: Copy all config files
  copy:
    src: "{{ item }}"
    dest: /etc/myapp/
  with_fileglob:
    - files/configs/*.conf

  # Modern equivalent using lookup
  loop: "{{ lookup('fileglob', 'files/configs/*.conf', wantlist=True) }}"
```

**`with_lines`** — iterate over the lines of output from a shell command run on the control node:

```yaml
- name: Process each line of output
  debug:
    msg: "{{ item }}"
  with_lines: cat /tmp/hostlist.txt

  # Modern equivalent
  loop: "{{ lookup('lines', 'cat /tmp/hostlist.txt', wantlist=True) }}"
```

**`with_sequence`** — generate a sequence of numbers or formatted strings:

```yaml
- name: Create numbered directories
  file:
    path: "/opt/myapp/worker-{{ item }}"
    state: directory
  with_sequence: start=1 end=5

  # Produces: worker-1, worker-2, worker-3, worker-4, worker-5

  # Modern equivalent using range filter
  loop: "{{ range(1, 6) | list }}"
```

**`with_nested`** — produce a cartesian product of two lists (every combination of items):

```yaml
- name: Create a vhost config for each app on each server
  template:
    src: vhost.conf.j2
    dest: "/etc/nginx/sites-available/{{ item[0] }}-{{ item[1] }}.conf"
  with_nested:
    - [ 'myapp', 'adminapp' ]
    - [ 'staging', 'production' ]

  # Produces: myapp-staging, myapp-production, adminapp-staging, adminapp-production

  # Modern equivalent
  loop: "{{ ['myapp', 'adminapp'] | product(['staging', 'production']) | list }}"
```

**`with_together`** — zip two lists together, pairing items by index:

```yaml
- name: Add DNS entries pairing hostnames with IPs
  lineinfile:
    path: /etc/hosts
    line: "{{ item[1] }} {{ item[0] }}"
  with_together:
    - [ 'web1', 'web2', 'db1' ]
    - [ '10.0.0.1', '10.0.0.2', '10.0.0.3' ]

  # Modern equivalent using zip filter
  loop: "{{ ['web1', 'web2', 'db1'] | zip(['10.0.0.1', '10.0.0.2', '10.0.0.3']) | list }}"
```

### When to Use `with_` vs `loop`

| Situation                     | Recommendation                                                    |
|-------------------------------|-------------------------------------------------------------------|
| Writing new playbooks         | Always use `loop`                                                 |
| Reading existing playbooks    | Recognise `with_*` but don't change it unless you have a reason   |
| `with_fileglob`, `with_lines` | No direct `loop` equivalent — use `lookup()` with `wantlist=True` |
| `with_sequence`               | Use `range()` filter with `loop`                                  |
| `with_nested`                 | Use `product()` filter with `loop`                                |
| `with_together`               | Use `zip()` filter with `loop`                                    |

The `with_*` keywords are not deprecated and will not be removed — they still work fine. The preference for `loop` is a
community convention, not a hard requirement.

---

## Error Handling

By default Ansible stops executing tasks on a host if any task fails. There are several ways to control this behaviour:

**`ignore_errors`** — Continue despite failure:

```yaml
- name: This might fail and that's okay
  command: /usr/bin/optional-check
  ignore_errors: true
```

**`failed_when`** — Define your own failure condition:

```yaml
- name: Run a script and only fail if exit code is 2
  command: /usr/bin/myscript
  register: result
  failed_when: result.rc == 2
```

**`changed_when`** — Define your own changed condition:

```yaml
- name: Run a command that never changes anything
  command: /usr/bin/readonly-check
  changed_when: false
```

**`block` / `rescue` / `always`** — Ansible's equivalent of try/catch/finally:

```yaml
- block:
    - name: Try to deploy
      command: /usr/bin/deploy.sh

  rescue:
    - name: Roll back if deploy failed
      command: /usr/bin/rollback.sh

  always:
    - name: Always send a notification
      debug:
        msg: "Deployment attempt finished"
```

---

## Flow Control: pause, wait_for, and wait_for_connection

These modules give you fine-grained control over timing and synchronisation within a playbook — essential for real-world
deployment workflows.

### `pause` — Halt Execution Temporarily

The `pause` module stops the playbook at a specific point, either for a fixed duration or until an operator confirms
it's safe to continue.

**Wait for a fixed duration:**

```yaml
- name: Wait 30 seconds for the service to stabilise
  pause:
    seconds: 30
```

**Wait for operator confirmation:**

```yaml
- name: Confirm before wiping the database
  pause:
    prompt: "About to drop all tables in production. Press Enter to continue, Ctrl+C to abort."
```

**Prompt for input and capture it as a variable:**

```yaml
- name: Ask for the release tag to deploy
  pause:
    prompt: "Enter the Git tag to deploy (e.g. v2.1.0)"
  register: release_tag

- name: Check out the chosen release
  git:
    repo: https://github.com/myorg/myapp.git
    dest: /opt/myapp
    version: "{{ release_tag.user_input }}"
```

The operator's input is available as `result.user_input`. This is a lightweight alternative to `vars_prompt` when you
need to collect a value mid-playbook based on something that has already happened.

> **Tip:** In non-interactive environments (CI/CD pipelines), `pause` with a `prompt` will time out automatically after
> 15 minutes and continue. Pass `--extra-vars "ansible_pause_timeout=60"` to set a shorter timeout.

---

### `wait_for` — Wait for a Condition on the Managed Host

`wait_for` polls until a port, path, or file condition becomes true on the target host. It's the right tool for waiting
on services that take time to start up.

**Wait for a port to open:**

```yaml
- name: Start the application
  service:
    name: myapp
    state: started

- name: Wait for the app to be listening on port 8080
  wait_for:
    port: 8080
    host: 127.0.0.1
    delay: 5
    timeout: 60
    state: started
```

**Wait for a port to close:**

```yaml
- name: Stop the application
  service:
    name: myapp
    state: stopped

- name: Wait for port 8080 to be released
  wait_for:
    port: 8080
    state: stopped
    timeout: 30
```

**Wait for a file to appear:**

```yaml
- name: Wait for the PID file to be created
  wait_for:
    path: /var/run/myapp/myapp.pid
    state: present
    timeout: 45
```

**Wait for a string to appear in a file:**

```yaml
- name: Wait for 'Startup complete' in the application log
  wait_for:
    path: /var/log/myapp/app.log
    search_regex: "Startup complete"
    timeout: 120
```

**Wait for a file to be absent:**

```yaml
- name: Wait for the lock file to be removed
  wait_for:
    path: /var/run/myapp/deploy.lock
    state: absent
    timeout: 300
```

Key parameters:

| Parameter         | Default     | Description                                          |
|-------------------|-------------|------------------------------------------------------|
| `port`            | —           | TCP port to check                                    |
| `host`            | `127.0.0.1` | Host to connect to                                   |
| `path`            | —           | File path to check                                   |
| `state`           | `started`   | `started`, `stopped`, `present`, `absent`, `drained` |
| `delay`           | `0`         | Seconds to wait before starting to poll              |
| `timeout`         | `300`       | Seconds before giving up                             |
| `sleep`           | `1`         | Seconds between poll attempts                        |
| `search_regex`    | —           | Regex string to look for in file content             |
| `connect_timeout` | `5`         | Seconds per connection attempt                       |

---

### `wait_for_connection` — Wait for SSH to Become Available

`wait_for_connection` is designed for situations where you've just rebooted a host or provisioned a new VM and need
Ansible to pause until it can actually reach the machine again. Unlike `wait_for`, it runs on the control node and tests
the full Ansible connection.

**Typical reboot pattern:**

```yaml
- name: Apply kernel updates
  apt:
    name: linux-image-generic
    state: latest
  register: kernel_update

- name: Reboot if kernel was updated
  reboot:
    msg: "Rebooting after kernel update"
    reboot_timeout: 120
  when: kernel_update.changed

- name: Wait for the machine to come back
  wait_for_connection:
    delay: 15
    timeout: 300
    sleep: 5
    connect_timeout: 10
```

> **Note:** For reboots, prefer the `reboot` module — it handles the full wait automatically. Use `wait_for_connection`
> directly when managing the connection lifecycle yourself, for example after provisioning a cloud VM.

---

## Includes and Imports

Large playbooks can be split into smaller files and pulled in using `include_tasks` or `import_tasks`.

**`import_tasks`** — Statically includes tasks at parse time:

```yaml
tasks:
  - import_tasks: tasks/install.yml
  - import_tasks: tasks/configure.yml
```

**`include_tasks`** — Dynamically includes tasks at runtime:

```yaml
tasks:
  - include_tasks: "tasks/{{ ansible_os_family }}.yml"
```

### include_vars — Load Variables Dynamically

```yaml
- name: Load OS-specific variables
  include_vars: "vars/{{ ansible_os_family }}.yml"

- name: Load environment-specific variables
  include_vars:
    file: "vars/{{ env }}.yml"
    name: env_config    # Optional: load into a named namespace
```

---

## Running Playbooks

```bash
# Basic run
ansible-playbook site.yml

# Specify an inventory
ansible-playbook site.yml -i inventory/production

# Limit to a specific host or group
ansible-playbook site.yml --limit webservers
ansible-playbook site.yml --limit web1

# Dry run — show what would change without making changes
ansible-playbook site.yml --check

# Show diff of file changes
ansible-playbook site.yml --check --diff

# Run only tasks with a specific tag
ansible-playbook site.yml --tags deploy

# Pass extra variables
ansible-playbook site.yml -e "app_version=2.1.0"

# Increase output verbosity (use -vvv for more detail)
ansible-playbook site.yml -v

# Start execution from a specific task (useful for resuming after failure)
ansible-playbook site.yml --start-at-task "Deploy application config"

# Step through tasks one at a time, confirming each
ansible-playbook site.yml --step
```

---

## A Complete Example

```yaml
---
- name: Deploy web application
  hosts: webservers
  become: true
  vars:
    app_version: "2.1.0"
    deploy_dir: /opt/myapp

  tasks:
    - name: Ensure deploy directory exists
      file:
        path: "{{ deploy_dir }}"
        state: directory
        mode: '0755'

    - name: Install dependencies
      apt:
        name:
          - nginx
          - python3
          - python3-pip
        state: present
        update_cache: true

    - name: Deploy application config
      template:
        src: templates/myapp.conf.j2
        dest: "{{ deploy_dir }}/myapp.conf"
      notify: Restart myapp

    - name: Check if app is already running
      stat:
        path: "{{ deploy_dir }}/myapp.pid"
      register: pid_file

    - name: Print deployment status
      debug:
        msg: "Deploying version {{ app_version }} to {{ inventory_hostname }}"

  handlers:
    - name: Restart myapp
      service:
        name: myapp
        state: restarted
```

---

---

# Deep Dive

---

## How Ansible Executes Playbooks Internally

Understanding what happens under the hood helps you write more efficient playbooks and debug problems faster.

### The Execution Pipeline

When you run `ansible-playbook site.yml`, Ansible goes through several phases before a single task runs on any host:

1. **Parse** — The playbook YAML is parsed and validated. `import_*` statements are resolved at this stage (statically),
   but `include_*` are not.
2. **Inventory** — The inventory is loaded and the hosts matching each play's `hosts` directive are resolved.
3. **Fact gathering** — Unless `gather_facts: false`, Ansible connects to each host and runs the `setup` module to
   collect system facts.
4. **Task execution** — Tasks run in order, one task across all targeted hosts (in parallel up to the fork limit) before
   the next task begins.
5. **Handler notification** — After all tasks in a play finish, any triggered handlers run once each.

### Fork-Based Parallelism

Ansible does not run all tasks on all hosts simultaneously. By default it uses 5 forks:

```bash
ansible-playbook site.yml -f 20
```

Or in `ansible.cfg`:

```ini
[defaults]
forks = 20
```

### `serial` — Rolling Deploys

```yaml
- name: Rolling deploy to web fleet
  hosts: webservers
  serial: 2           # Process 2 hosts at a time
  # serial: "25%"     # Or a percentage of the group
  # serial: [1, 5, 10] # Canary pattern: 1 first, then 5, then 10 at a time
```

### The `any_errors_fatal` and `max_fail_percentage` Interplay

```yaml
- name: Deploy with strict failure handling
  hosts: webservers
  any_errors_fatal: true

- name: Deploy with tolerance for some failures
  hosts: webservers
  max_fail_percentage: 10
```

---

## Jinja2 Templating In Depth

### Filters

```yaml
- debug:
    msg: "{{ some_list | length }}"
    msg: "{{ some_string | default('fallback') }}"
    msg: "{{ path | basename }}"
    msg: "{{ path | dirname }}"
    msg: "{{ some_list | join(', ') }}"
    msg: "{{ some_dict | dict2items }}"
    msg: "{{ password | password_hash('sha512') }}"
    msg: "{{ some_list | unique }}"
    msg: "{{ some_list | flatten }}"
    msg: "{{ some_list | selectattr('active') | list }}"
```

### Tests

```yaml
when: my_var is defined
when: my_var is undefined
when: result is succeeded
when: result is failed
when: result is changed
when: my_path is file
when: my_path is directory
when: my_string is match("^v[0-9]")
when: my_string is search("error")
```

### Lookups

```yaml
vars:
  ssl_key: "{{ lookup('file', '/etc/ssl/private/myapp.key') }}"
  github_token: "{{ lookup('env', 'GITHUB_TOKEN') }}"
  db_password: "{{ lookup('hashi_vault', 'secret=secret/myapp/db:password') }}"
```

---

## Asynchronous Tasks

```yaml
- name: Start a long backup job in the background
  command: /usr/bin/backup.sh
  async: 3600
  poll: 0
  register: backup_job

- name: Check if the backup job has finished
  async_status:
    jid: "{{ backup_job.ansible_job_id }}"
  register: job_result
  until: job_result.finished
  retries: 30
  delay: 60
```

---

## `until` / `retries` / `delay` — Polling for a Condition

```yaml
- name: Wait for the API to report healthy
  uri:
    url: http://localhost:8080/health
    return_content: true
  register: health_check
  until: health_check.status == 200 and 'ok' in health_check.content
  retries: 12
  delay: 10
```

---

## Privilege Escalation In Depth

```yaml
- name: Example with full privilege escalation options
  command: /opt/app/admin-task.sh
  become: true
  become_method: sudo
  become_user: app_admin
  become_flags: "-H -S"
```

| Method  | Use case                                             |
|---------|------------------------------------------------------|
| `sudo`  | Default; requires sudoers config on the managed host |
| `su`    | Use `su` instead of `sudo`                           |
| `doas`  | OpenBSD default; BSD alternative to sudo             |
| `runas` | Windows                                              |
| `pbrun` | BeyondTrust PowerBroker                              |

---

## Secrets Management with `ansible-vault`

```bash
ansible-vault encrypt vars/secrets.yml
ansible-vault create vars/secrets.yml
ansible-vault edit vars/secrets.yml
ansible-vault view vars/secrets.yml
ansible-vault rekey vars/secrets.yml
```

### Encrypting a Single Value

```bash
ansible-vault encrypt_string 'supersecret123' --name 'db_password'
```

```yaml
db_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  61383433386637316637663736323636...
```

### Running Playbooks with Vault

```bash
ansible-playbook site.yml --ask-vault-pass
ansible-playbook site.yml --vault-password-file ~/.vault_pass
ansible-playbook site.yml --vault-id dev@~/.vault_pass_dev --vault-id prod@~/.vault_pass_prod
```

---

## Debugging Techniques

### The `debug` Module

```yaml
- name: Print a variable
  debug:
    var: ansible_default_ipv4.address

- name: Print a message with interpolation
  debug:
    msg: "Deploying {{ app_version }} to {{ inventory_hostname }}"

- name: Show only when verbose
  debug:
    msg: "This only shows with -v or higher"
    verbosity: 1
```

### The `assert` Module

```yaml
- name: Validate required variables are set
  assert:
    that:
      - app_version is defined
      - app_version | length > 0
      - deploy_env in ['staging', 'production']
    fail_msg: "app_version and deploy_env (staging|production) must be set"
    success_msg: "Validation passed"
```

### Checking Facts

```bash
ansible webservers -m setup
ansible webservers -m setup -a "filter=ansible_distribution*"
```

---

## Strategy Plugins

### `linear` (default)

Task 1 runs on all hosts → Task 2 runs on all hosts → ...

### `free`

Each host runs through its task list as fast as it can, independently of other hosts:

```yaml
- name: Update packages across a large fleet
  hosts: all
  strategy: free

  tasks:
    - name: Run apt upgrade
      apt:
        upgrade: dist
        update_cache: true
```

### `debug`

Drops you into an interactive debugger when a task fails:

```yaml
- name: Debug a tricky play
  hosts: webservers
  strategy: debug
```

Inside the debugger:

- `p variable_name` — print a variable
- `update_task` — re-run the current task
- `continue` — continue execution
- `quit` — stop the playbook

---

## Pre-tasks, Post-tasks, and Play Ordering

```yaml
- name: Full deployment play
  hosts: webservers
  become: true

  pre_tasks:
    - name: Remove host from load balancer
      command: /usr/bin/lb-remove {{ inventory_hostname }}
      delegate_to: loadbalancer.example.com

  tasks:
    - name: Deploy the application
      import_tasks: tasks/deploy.yml

  post_tasks:
    - name: Re-add host to load balancer
      command: /usr/bin/lb-add {{ inventory_hostname }}
      delegate_to: loadbalancer.example.com

    - name: Verify the application is healthy
      uri:
        url: "http://{{ inventory_hostname }}:8080/health"
        status_code: 200
```

Full execution order: `pre_tasks` → role tasks → `tasks` → `post_tasks`.