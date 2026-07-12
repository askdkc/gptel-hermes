# maedaweb Update Reference

## Trigger phrases

Use this reference when the user says:

- `maedaweb更新`
- `Maedawebを更新して`
- `maedawebをpullしてsyncして`
- asks to run the remembered Maedaweb update task

## Workflow

Run exactly this command:

```bash
pwd && git pull && ~/tools/syncmaeda.sh
```

with working directory:

```text
/home/ubuntu/Sites/maedaweb
```

Equivalent Hermes terminal call:

```json
{
  "command": "pwd && git pull && ~/tools/syncmaeda.sh",
  "timeout": 600,
  "workdir": "/home/ubuntu/Sites/maedaweb"
}
```

## Expected successful output shape

Typical successful run may include:

```text
/home/ubuntu/Sites/maedaweb
Already up to date.
sending incremental file list

sent ... bytes  received ... bytes  ... bytes/sec
total size is ...  speedup is ...
```

## Reporting

Report succinctly in Japanese:

- `git pull` result, e.g. `Already up to date` or changed files
- `~/tools/syncmaeda.sh` success/failure based on exit code
- rsync summary lines such as `sent ...`, `total size ...`

## Pitfalls

- Do not run from `/home/ubuntu` or any other directory; set `workdir` explicitly.
- Do not split commands unless debugging; the chained command prevents syncing after a failed pull.
- Do not claim success from memory. Always run the command and use real output.
