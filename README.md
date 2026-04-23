# nvidia-basic

Personal knowledge base for operating NVIDIA GPU instances on AWS — driver management, `nvidia-smi`, DCGM, CloudWatch integration, and troubleshooting, all built from real hands-on experience.

---

## Structure

```
nvidia-basic/
├── docs/
│   ├── driver/          # Driver installation, version management, Fabric Manager
│   ├── smi/             # nvidia-smi usage, query options, monitoring, GPU reset
│   ├── dcgm/            # DCGM setup, field groups, dcgmi CLI
│   ├── monitoring/      # CloudWatch GPU metrics, DCGM Exporter + Prometheus
│   ├── cuda/            # CUDA/driver compatibility, Container Toolkit
│   └── troubleshooting/ # Xid errors, driver crash recovery, AWS host replacement
│
├── scripts/             # Automation scripts (health check, CloudWatch publisher)
├── templates/           # Document scaffolding templates
├── rules/               # Writing conventions (style, nvidia-smi/DCGM code rules)
├── agents/              # Claude agent prompts (doc writer, troubleshooter)
└── .claude/
    └── commands/        # Custom slash commands (/new-doc, /new-runbook, ...)
```

---

## Documents

### Driver
| File | Topic |
|------|-------|
| [`nvidia-driver-install-al2023.md`](docs/driver/nvidia-driver-install-al2023.md) | Installing NVIDIA drivers on AL2023 with DKMS |
| [`nvidia-driver-version-management.md`](docs/driver/nvidia-driver-version-management.md) | Driver branch selection, upgrade & rollback procedures |
| [`nvidia-fabric-manager.md`](docs/driver/nvidia-fabric-manager.md) | Fabric Manager for NVSwitch instances (p4d, p5) |

### nvidia-smi
| File | Topic |
|------|-------|
| [`nvidia-smi-basics.md`](docs/smi/nvidia-smi-basics.md) | Basic usage, output interpretation, Persistence Mode |
| [`nvidia-smi-query.md`](docs/smi/nvidia-smi-query.md) | `--query-gpu` field reference, CloudWatch publish script |
| [`nvidia-smi-monitoring.md`](docs/smi/nvidia-smi-monitoring.md) | `dmon`/`pmon` loop monitoring, timestamped log collection |
| [`nvidia-smi-gpu-reset.md`](docs/smi/nvidia-smi-gpu-reset.md) | GPU reset (`-r`), MIG mode partitioning |

### DCGM
| File | Topic |
|------|-------|
| [`dcgm-setup.md`](docs/dcgm/dcgm-setup.md) | Installing DCGM, starting `nv-hostengine`, group management |
| [`dcgm-field-groups.md`](docs/dcgm/dcgm-field-groups.md) | Field ID reference table, `dcgmi` health check & diagnostics |

### Monitoring
| File | Topic |
|------|-------|
| [`cw-gpu-metrics.md`](docs/monitoring/cw-gpu-metrics.md) | Collecting GPU metrics in CloudWatch via CWAgent + DCGM |
| [`dcgm-exporter-prometheus.md`](docs/monitoring/dcgm-exporter-prometheus.md) | DCGM Exporter on EKS, Prometheus ServiceMonitor, Grafana dashboards |

### CUDA
| File | Topic |
|------|-------|
| [`cuda-driver-compatibility.md`](docs/cuda/cuda-driver-compatibility.md) | CUDA Toolkit ↔ driver version compatibility matrix |
| [`nvidia-container-toolkit.md`](docs/cuda/nvidia-container-toolkit.md) | Container Toolkit setup for Docker/containerd/EKS |

### Troubleshooting
| File | Topic |
|------|-------|
| [`xid-error-codes.md`](docs/troubleshooting/xid-error-codes.md) | Xid error code classification, AWS host replacement decision matrix |
| [`driver-crash-recovery.md`](docs/troubleshooting/driver-crash-recovery.md) | Step-by-step recovery: GPU reset → module reload → reinstall |
| [`aws-host-replacement.md`](docs/troubleshooting/aws-host-replacement.md) | Stop&Start procedure, Scheduled Event handling, ASG Standby |

---

## Scripts

| Script | Description |
|--------|-------------|
| [`gpu-health-check.sh`](scripts/gpu-health-check.sh) | One-shot health check — driver, ECC, Xid, Fabric Manager status |
| [`gpu-metrics-to-cw.sh`](scripts/gpu-metrics-to-cw.sh) | Publish `nvidia-smi` metrics to CloudWatch (cron-friendly) |

```bash
# Run health check
sudo bash scripts/gpu-health-check.sh

# Publish metrics manually
bash scripts/gpu-metrics-to-cw.sh
```

---

## Slash Commands (Claude Code)

| Command | Usage | Description |
|---------|-------|-------------|
| `/new-doc` | `/new-doc smi mig-mode` | Scaffold a new knowledge document |
| `/new-runbook` | `/new-runbook driver upgrade` | Generate an operational runbook |
| `/add-troubleshooting` | `/add-troubleshooting docs/smi/nvidia-smi-basics.md <symptom>` | Append a troubleshooting entry |
| `/search-kb` | `/search-kb Xid 48` | Search the knowledge base by keyword |

---

## Key Concepts

### Xid Error Quick Reference

| Xid | Name | AWS Action |
|-----|------|-----------|
| 13 | Graphics Engine Exception | Rerun with `CUDA_LAUNCH_BLOCKING=1` |
| 31 | GPU memory page fault | Check application code |
| 48 | Double Bit ECC Error | **Stop & Start immediately** |
| 63 | GPU Row Remapping | `nvidia-smi -r`, verify pending = 0 |
| 74 | NVLink Error | Check `nvidia-smi nvlink -e`, Stop & Start |
| 79 | GPU fell off the bus | **Stop & Start immediately** |

### Driver Branch Selection

| Branch | Major Version | Use Case |
|--------|--------------|----------|
| Production (recommended) | 470, 510, 525, 535, 550, 570 | Production workloads |
| New Feature | 545, 560 | Test environments only |

### GPU Instance Families

| Family | GPU | NVSwitch | Fabric Manager |
|--------|-----|----------|---------------|
| p4d / p4de | A100 (8x) | ✅ | Required |
| p5 | H100 (8x) | ✅ | Required |
| g5 | A10G | ❌ | Not needed |
| g4dn | T4 | ❌ | Not needed |

---

## Writing Principles

1. **Experience-based** — only document issues encountered in real operations
2. **Reproducible commands** — every `nvidia-smi` command is copy-paste ready
3. **Root cause first** — explain *why*, not just *what* happened
4. **Monitoring included** — every document contains CloudWatch metrics and alarm setup
5. **Korean with English terms** — primary language Korean, technical terms in English

See [`rules/doc-writing.md`](rules/doc-writing.md) and [`rules/nvidia-conventions.md`](rules/nvidia-conventions.md) for detailed guidelines.

---

## Backlog

- `docs/driver/nvidia-driver-efa.md` — EFA + GPU driver configuration (p4d, p5)
- `docs/smi/nvidia-smi-mig.md` — MIG partitioning in depth (A100, H100)
- `docs/monitoring/gpu-alarm-patterns.md` — GPU alarm pattern cookbook
- `docs/cuda/cuda-multi-version.md` — Running multiple CUDA versions side-by-side
