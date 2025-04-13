# Define mocks needed for tests
# This file should be required in test_helper.exs

Mox.defmock(WandererNotifier.Data.MockRepository, for: WandererNotifier.Data.RepositoryBehaviour)
Mox.defmock(WandererNotifier.Cache.MockKillmail, for: WandererNotifier.Cache.Behaviour)

Mox.defmock(WandererNotifier.Killmail.Processing.MockProcessor,
  for: WandererNotifier.Killmail.Processing.ProcessorBehaviour
)

Mox.defmock(WandererNotifier.Killmail.Processing.MockPersistence,
  for: WandererNotifier.Killmail.Processing.PersistenceBehaviour
)

Mox.defmock(WandererNotifier.Config.MockFeatures, for: WandererNotifier.Config.FeaturesBehaviour)

Mox.defmock(WandererNotifier.Data.Cache.MockHelpers,
  for: WandererNotifier.Data.Cache.HelpersBehaviour
)
