# Introduction to Ansible

## What is Ansible?

Ansible is an open-source **IT automation tool** developed by Michael DeHaan and first released in 2012. Red Hat acquired it in 2015, and it has since become one of the most widely adopted automation platforms in the industry.

At its core, Ansible lets you describe the desired state of your infrastructure and systems in plain, human-readable files — then automatically makes that state a reality across any number of machines simultaneously.

---

## What Problem Does It Solve?

Managing infrastructure manually — SSHing into servers one by one, running commands, editing config files — doesn't scale. It's slow, error-prone, and nearly impossible to repeat consistently across dozens or hundreds of machines.

Ansible addresses this by allowing you to:

- **Automate repetitive tasks** like installing software, configuring services, and managing users
- **Ensure consistency** across all your servers (every machine is configured identically)
- **Version-control your infrastructure** by storing automation logic in files alongside your code
- **Reduce human error** by replacing manual steps with reliable, repeatable scripts

---

## Key Characteristics

### Agentless
Unlike many other automation tools (Puppet, Chef), Ansible requires **no agent software** installed on the machines it manages. It communicates over standard **SSH** (or WinRM for Windows), which means zero setup overhead on target machines.

### Idempotent
Ansible tasks are designed to be **idempotent** — running them multiple times produces the same result as running them once. If a package is already installed, Ansible won't reinstall it. This makes automation safe to run repeatedly without side effects.

### Declarative & Procedural
Ansible supports both styles. You can describe *what* you want (install nginx, ensure a user exists) and also define *how* tasks should run in sequence.

### Push-Based
The control node (your laptop or a CI server) **pushes** changes out to managed nodes. There's no need for agents polling a central server.

---

## Core Concepts

### Inventory
An **inventory** is a list of the hosts (servers, VMs, containers) that Ansible manages. It can be a simple static file or dynamically generated from cloud providers.

```ini
# Example static inventory
[webservers]
web1.example.com
web2.example.com

[databases]
db1.example.com
```

### Playbooks
**Playbooks** are YAML files that describe automation tasks. They are the heart of Ansible — you write a playbook to express what should happen and on which hosts.

```yaml
# Example playbook: install and start nginx
- name: Configure web servers
  hosts: webservers
  become: true

  tasks:
    - name: Install nginx
      apt:
        name: nginx
        state: present

    - name: Start nginx service
      service:
        name: nginx
        state: started
        enabled: true
```

### Modules
**Modules** are the building blocks of tasks — pre-written units of work that Ansible ships with. There are hundreds of built-in modules covering everything from package management (`apt`, `yum`) to cloud resources (`aws_ec2`, `azure_rm`) to file operations (`copy`, `template`).

### Roles
**Roles** are a way to organise playbooks into reusable, shareable units. A role bundles together tasks, variables, templates, and handlers for a specific purpose (e.g., a "postgresql" role or a "nginx" role).

### Variables
Ansible supports **variables** at multiple levels (inventory, playbook, role, command line), allowing you to write flexible automation that adapts to different environments (dev, staging, production).

### Templates
Using the **Jinja2** templating engine, Ansible can generate dynamic configuration files from templates, substituting variables at runtime.

### Handlers
**Handlers** are special tasks that only run when triggered by another task — typically used to restart a service only when its configuration changes.

---

## Common Use Cases

| Use Case | Description |
|---|---|
| **Configuration Management** | Ensure all servers have the correct packages, users, and config files |
| **Application Deployment** | Deploy code, restart services, run migrations |
| **Provisioning** | Spin up cloud infrastructure (EC2 instances, VPCs, DNS records) |
| **Orchestration** | Coordinate multi-step workflows across multiple systems in the right order |
| **Security & Compliance** | Enforce security policies, manage SSH keys, apply patches |
| **CI/CD Integration** | Trigger deployments as part of a pipeline (Jenkins, GitLab CI, GitHub Actions) |

---

## Ansible vs. Similar Tools

| Feature | Ansible | Puppet | Chef | Terraform |
|---|---|---|---|---|
| Agent required | No | Yes | Yes | No |
| Language | YAML | DSL (Ruby-based) | Ruby DSL | HCL |
| Push vs Pull | Push | Pull | Pull | Push |
| Primary focus | Config + orchestration | Config management | Config management | Infrastructure provisioning |
| Learning curve | Low | High | High | Medium |

> **Note:** Ansible and Terraform are often used together — Terraform provisions infrastructure, and Ansible configures it.

---

## How Ansible Works (The Execution Flow)

```
You (Control Node)
       │
       │  SSH / WinRM
       ▼
 Managed Nodes
 (web1, db1, ...)
       │
       ▼
Ansible pushes small Python scripts (modules),
executes them, collects results, cleans up.
No agent stays behind.
```

1. You run `ansible-playbook my-playbook.yml`
2. Ansible reads the inventory to find target hosts
3. It connects to each host over SSH
4. It uploads and executes the required modules
5. Results are collected and reported back
6. Temporary files are cleaned up

---

## Project Structure (A Typical Layout)

```
project/
├── inventory/
│   ├── production
│   └── staging
├── group_vars/
│   ├── all.yml
│   └── webservers.yml
├── roles/
│   ├── nginx/
│   │   ├── tasks/main.yml
│   │   ├── templates/nginx.conf.j2
│   │   └── handlers/main.yml
│   └── postgresql/
│       └── tasks/main.yml
├── site.yml          ← master playbook
└── deploy.yml        ← deployment playbook
```

---

## Getting Started

### Installation

```bash
# On Ubuntu/Debian
sudo apt update && sudo apt install ansible

# On macOS (with Homebrew)
brew install ansible

# Via pip (Python package manager)
pip install ansible
```

### Your First Command (Ad-hoc)

Before writing playbooks, you can run **ad-hoc commands** to test connectivity or perform quick tasks:

```bash
# Ping all hosts in inventory
ansible all -m ping

# Check disk space on webservers
ansible webservers -m shell -a "df -h"

# Install a package on all hosts
ansible all -m apt -a "name=htop state=present" --become
```

### Your First Playbook

Save the following as `hello.yml` and run it with `ansible-playbook hello.yml`:

```yaml
- name: My first playbook
  hosts: localhost
  gather_facts: false

  tasks:
    - name: Print a message
      debug:
        msg: "Hello from Ansible!"
```

---

## Ansible Galaxy

**Ansible Galaxy** (galaxy.ansible.com) is the official hub for sharing and downloading community-written roles and collections. Instead of writing automation for common tasks from scratch, you can pull in well-tested roles:

```bash
# Install a community role
ansible-galaxy install geerlingguy.nginx
```

---

## Key Strengths & Limitations

**Strengths**
- Extremely low barrier to entry — YAML is readable by non-developers
- No agents = easy adoption, no maintenance overhead on managed nodes
- Massive ecosystem (thousands of modules, Galaxy roles)
- Works well for both small setups and large enterprises
- Strong integration with cloud providers and CI/CD tools

**Limitations**
- Can be slower than agent-based tools at very large scale (SSH overhead)
- YAML can become unwieldy for very complex logic
- Error messages can sometimes be cryptic for beginners
- Not a full substitute for infrastructure provisioning tools like Terraform

---

## Further Reading

- [Official Ansible Documentation](https://docs.ansible.com/)
- [Ansible Galaxy](https://galaxy.ansible.com/)
- *Ansible for DevOps* by Jeff Geerling (highly recommended book)
- [GitHub: ansible/ansible](https://github.com/ansible/ansible)