# FreeSWITCH configuration

The container copies its complete, version-matched default configuration into
this directory on the first start. Files here are writable and persist on the
host. After most XML edits, run:

```bash
docker compose exec -T freeswitch fs_cli -x reloadxml
```
