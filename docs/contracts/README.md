# The six compatibility contracts

These documents define what "drop-in replacement" means, extracted from the C# source at the
pinned upstream commit (see [../UPSTREAM.md](../UPSTREAM.md)). Any code change that would
violate a contract is a bug by definition, and any upstream change that moves a contract
updates the doc *first*, then the code.

1. [convars.md](convars.md): all 47 settings, types, defaults, coercion quirks
2. [permissions.md](permissions.md): 297 ACE permissions + 3 supplementary, naming and implication rules
3. [events.md](events.md): the full `vMenu:*` network/local event protocol with signatures
4. [kvp-saves.md](kvp-saves.md): KVP key patterns and Newtonsoft JSON shapes (golden fixtures in `tests/fixtures/`)
5. [config-files.md](config-files.md): `config/*.json` schemas and error tolerance
6. [commands-keymappings.md](commands-keymappings.md): command names and key-mapping persistence keys
