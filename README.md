# Ansible tutorial

This repository contains notes about Ansible for learning purposes.

In order to run the examples, navigate to the [lab](./lab) folder:

```bash
cd ./lab
```

Start up the Docker containers:

```bash
docker compose up -d
```

Then navigate into the control container:

```bash
docker exec -it ansible-control bash
```

Then run any playbook in there, for example:

```bash
ansible-playbook /ansible/playbooks/with_together_demo.yml
```

Once done, exit and pull down the containers:

```bash
docker compose down
```

## Table of contents

1. [Introduction](./chapters/introduction/Introduction.md)

> Contains a high level overview of different parts that make up Ansible.

2. [Architecture](./chapters/architecture/Architecture.md)

> Describes what different elements are.

3. [Playbooks](./chapters/playbooks/Playbooks.md)

> Describes playbooks and tasks.
