{ upstream }:
upstream.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./patches/host-managed-resources.patch ];

  preCheck =
    (old.preCheck or "")
    + (
      if upstream.stdenv.hostPlatform.isLinux then
        ''
          # effect-tsgo bundles native checkers with non-Nix ELF interpreters.
          tsgoPlatform=linux-${upstream.stdenv.hostPlatform.node.arch}
          for checker in node_modules/.pnpm/@effect+tsgo-"$tsgoPlatform"@*/node_modules/@effect/tsgo-"$tsgoPlatform"; do
            [[ ! -d "$checker" ]] || autoPatchelf "$checker"
          done
        ''
      else
        ""
    );

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    pnpm --filter t3 typecheck
    pnpm exec vp fmt --check \
      apps/server/src/process/agentScope.ts \
      apps/server/src/process/agentScope.test.ts
    pnpm exec vp test run apps/server/src/process/agentScope.test.ts
    runHook postCheck
  '';
})
