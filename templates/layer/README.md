# Layer

A KingsScript layer. Register it with `kings layer add <path>`; see the KingsScript README
for the full contract.

| File | Role |
|---|---|
| `layer.env` | `LAYER_NAME`, the name shown in `kings help` and used in logs |
| `main.sh` | The layer's commands |
| `hooks/` | Git hooks (`<hook>.sh`) |
| `checkup.sh` | Periodic tasks |
