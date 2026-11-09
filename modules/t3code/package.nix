{ upstream }:
upstream.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./patches/host-managed-resources.patch ];

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
