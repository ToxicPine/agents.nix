# T3 Code resource policy

The default `services.t3code.package` applies the source patch in
`patches/host-managed-resources.patch` to the pinned T3 Code release. The same
package is available as `packages.<system>.t3code`.

T3 leaves these systemd properties untouched by default. This lets Nix-managed
slice units govern resource use without T3 generating higher-priority runtime
overrides.

| Server environment variable | Property | Slice |
| --- | --- | --- |
| `T3CODE_AGENT_SLICE_MEMORY_HIGH` | `MemoryHigh` | `app-t3code-agents.slice` |
| `T3CODE_AGENT_SLICE_MEMORY_MAX` | `MemoryMax` | `app-t3code-agents.slice` |
| `T3CODE_AGENT_SLICE_CPU_WEIGHT` | `CPUWeight` | `app-t3code.slice` |
| `T3CODE_AGENT_SLICE_IO_WEIGHT` | `IOWeight` | `app-t3code.slice` |
| `T3CODE_AGENT_SLICE_TASKS_MAX` | `TasksMax` | `app-t3code.slice` |

Leave every variable absent to use the host's policy. Empty or whitespace-only
strings and the case-insensitive strings `null` and `unset` also omit a property.
Omitting a property does not set it to `infinity` or erase an existing host limit.

For an explicit runtime override, use systemd's native value syntax, for example
`8G`, `75%`, `1000`, or `infinity` where the property supports it. Values are passed
as individual process arguments, not interpreted by a shell. Systemd validates
them; rejected overrides are logged without falling back to T3's former defaults.
Only properties with configured values are sent to systemd.

```nix
# Optional: omit this entirely when the slice units already define your policy.
systemd.user.services.t3code.environment = {
  T3CODE_AGENT_SLICE_MEMORY_MAX = "32G";
  T3CODE_AGENT_SLICE_CPU_WEIGHT = "1000";
};
```

All T3 servers sharing the same systemd user manager share these slices. Configure
them consistently. Changes take effect when T3 restarts and initializes agent
scopes. This Linux-only policy change retains agent scope creation, delegation,
stop timeouts, OOM handling, and cleanup.

Existing runtime overrides created by an older T3 installation survive a service
restart. Remove the known T3-generated files under
`/run/user/<uid>/systemd/user.control/app-t3code.slice.d/` and
`app-t3code-agents.slice.d/`, then run `systemctl --user daemon-reload`, or reboot.
Inspect their contents first and preserve any administrator-managed overrides.
The patched server will not recreate omitted properties.

`nix build .#t3code` builds the patched application and runs the server typecheck,
format checks for the patched files, and the agent scope tests. `nix flake check`
runs the same package check.
