# PIE Backend Freeze Map

This file defines the backend surfaces that must remain stable for the first public workbench.

## Stable surfaces

- `pie.ps1`
- `scripts/pie_chat_v1.ps1`
- `scripts/pie_agent_start_v1.ps1`
- `scripts/pie_agent_send_v1.ps1`
- `scripts/pie_agent_stop_v1.ps1`
- `scripts/pie_memory_policy_v1.ps1`
- `scripts/pie_memory_accept_v1.ps1`
- `scripts/pie_conversation_open_v1.ps1`
- `scripts/pie_verify_init_v1.ps1`
- `scripts/pie_model_matrix_stress_v1.ps1`

## Adapter rule

Every model backend must conform to `schemas/pie.adapter.contract.v1.json`.

## Release language

PIE is a local AI runtime and workbench. Avoid internal build-stage language in public docs.
