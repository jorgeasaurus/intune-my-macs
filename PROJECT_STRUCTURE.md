# Intune My Mac - Project Structure

This document outlines the high-level folder structure for organizing payloads, scripts, applications, and configurations across Microsoft 365 services for early development.

## 📁 Root Directory Structure

```
intune-my-mac/
├── 📁 src/                           # Source code for the automation tool
│   └── 📁 utils/                     # Utility functions, modules or tools
│
├── 📁 configurations/                # Configuration library
│   ├── 📁 intune/                    # Microsoft Intune configurations
│   ├── 📁 entra/                     # Entra ID configurations  
│   ├── 📁 purview/                   # Microsoft Purview configurations
│   ├── 📁 defender/                  # Microsoft Defender configurations
│
├── 📁 applications/                  # Application packages
│   ├── 📁 utilities/                 # System utilities
│   ├── 📁 line of business/          # Sample LOB apps
│   └── 📁 scripts/                   # Scripted app installations
│
├── 📁 scripts/                       # Automation scripts
│   ├── 📁 configuration/             # Configuration scripts
│   ├── 📁 validation/                # Pre/post validation
│   └── 📁 reporting/                 # Status and reporting
│
├── 📁 custom attributes/             # Custom attribute scripts
│   ├── 📁 TBC/                       # Configuration scripts
│   └── 📁 TBC/                       # Status and reporting
│
├── 📁 docs/                          # Documentation
└── 📁 tools/                         # Development utilities
```

