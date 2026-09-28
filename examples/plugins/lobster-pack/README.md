# Reef Lobsters

A native Lobster Pack with two original Clawmojis: Coral (self-contained SVG) and
Tide (a three-frame PNG sprite atlas). All artwork in this example is original
and available under the repository's MIT license.

From the repository root, install the example in your development profile:

```sh
openclaw plugins install ./examples/plugins/lobster-pack
```

Reload plugins or restart the Gateway, then open **LobsterDex**. The pack appears
under **Lobster Packs**. Previewing it does not record an encounter.

The identities available to Control UI plugin consumers are:

- `reef-lobsters/reef/coral`
- `reef-lobsters/reef/tide`

The native entrypoint intentionally registers no runtime hooks. The manifest
contributes the artwork; core reads and validates it before plugin execution.
Keep the entrypoint and `openclaw.extensions` declaration when publishing a native
package. A pack is not a new bundle or installer format.

Edit `reef.json` and the packaged assets, then explicitly reload the plugin to
publish a new catalog generation. Core serves captured bytes from that generation
so an on-disk edit cannot silently replace artwork already admitted by the host.
