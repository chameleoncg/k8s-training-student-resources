## 📄 Student Cheat Sheet: Helm Basics

### 1. Essential Commands
| Command | What it does |
| :--- | :--- |
| `helm create <name>` | Create a boilerplate chart directory. |
| `helm install <release-name> <path>` | Deploy a chart to the cluster. |
| `helm upgrade <release-name> <path>` | Update a release with new values/templates. |
| `helm list` | Show all running releases. |
| `helm rollback <release-name> <rev>` | Revert to a previous version (e.g., `rev 1`). |
| `helm uninstall <release-name>` | Delete the release and its history. |

### 2. Debugging (The "Dry-Run" trick)
Before you deploy, see what the YAML *will* look like:
```bash
helm install --debug --dry-run my-test ./my-chart
```

### 3. Basic Template Syntax
* **Accessing Values:** `{{ .Values.service.port }}`
* **Release Info:** `{{ .Release.Name }}` (The name you gave the install)
* **Pipes (Functions):** `{{ .Values.name | upper | quote }}` (Makes it uppercase and adds quotes)
* **Default Values:** `{{ .Values.count | default 3 }}`
