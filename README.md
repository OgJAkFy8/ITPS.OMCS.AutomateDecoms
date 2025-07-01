# Automated Decom Scripts

This repository contains all scripts and modules for automated VM and Active Directory decommissioning, including:
- System prep and validation (DNS, AD, folder, etc.)
- Logging and export
- Modular decommissioning workflows for VMs and AD objects
- Team-friendly, handoff-ready PowerShell scripts

## Usage
- Use `Start-DecomPrep.ps1` to gather and validate all system information before decommissioning.
- Use the appropriate decom script (e.g., `Start-VMDecomProcess-Clean.ps1`) to perform the decommissioning, passing the prep object as input.

All scripts are designed for PowerShell 5.1 compatibility and operational handoff.
