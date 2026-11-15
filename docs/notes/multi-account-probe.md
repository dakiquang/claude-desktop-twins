# Reading the native multi-account flag

Claude Desktop passes its feature table to its helper processes as a JSON argument:

```text
--desktop-features={"launch":{"status":"supported"}, ... "multiAccount":{"status":"unavailable"}, ...}
```

On 5.11492.5 the value was `unavailable`. The flag is behind a staged rollout.

`cdt doctor` reads it with:

```bash
ps -axo command= | grep -o '"multiAccount":{"status":"[a-z_]*"' | head -n 1
```

- No Claude process running: the status is unknown, and `doctor` says so.
- `supported`: Claude has its own multi-account support; `doctor` warns that the tool
  may no longer be needed.
- Anything else is reported as is.
