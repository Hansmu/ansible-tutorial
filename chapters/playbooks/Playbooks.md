# Ansible Playbooks

## What is a Playbook?

A playbook is a YAML file that describes automation tasks — what should happen, on which hosts, and in what order. It is the primary way you interact with Ansible for anything beyond a quick one-off ad-hoc command.

Where an ad-hoc command runs a single module once, a playbook can orchestrate dozens of tasks across multiple groups of hosts, handle errors, make decisions based on conditions, and be run repeatedly with consistent results.

---

## Structure of a Playbook

A playbook is made up of one or more **plays**. Each play targets a group of hosts and defines a list of tasks to run against them. Multiple plays in the same file allow you to do different things to different groups of hosts in sequence.

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
  vars:                    # Variables scoped to this play
    http_port: 80
  environment:             # Environment variables set on the managed node
    APP_ENV: production
  serial: 2                # How many hosts to act on at a time
  any_errors_fatal: true   # Stop all hosts if any host fails
  max_fail_percentage: 20  # Allow up to 20% of hosts to fail before aborting
```

---

## Tasks

Tasks are the individual steps within a play. Each task calls exactly one module and gives it a name for readability in output.

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

---

## Handlers

Handlers are special tasks that only run when triggered by a `notify` directive, and only if the notifying task actually made a change. They always run at the end of the play, regardless of where in the task list the `notify` appeared.

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

Even if both tasks notify the same handler, the handler only runs once. This prevents unnecessary service restarts when multiple config files change in the same play.

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

## Includes and Imports

Large playbooks can be split into smaller files and pulled in using `include_tasks` or `import_tasks`.

**`import_tasks`** — Statically includes tasks at parse time. All tasks are loaded upfront, so tags and conditionals apply to the imported tasks directly:
```yaml
tasks:
  - import_tasks: tasks/install.yml
  - import_tasks: tasks/configure.yml
```

**`include_tasks`** — Dynamically includes tasks at runtime. Useful when the file to include depends on a variable:
```yaml
tasks:
  - include_tasks: "tasks/{{ ansible_os_family }}.yml"
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