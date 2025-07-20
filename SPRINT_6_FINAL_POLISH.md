# Sprint 6: Final Polish & Production Readiness
**Duration**: 1 week (5 working days)  
**Team Size**: 1-2 developers  
**Risk Level**: Low  
**Prerequisites**: Sprint 5 at 95% completion

## Sprint Goals

1. Fix remaining 80 test failures to achieve 100% passing tests
2. Create comprehensive performance benchmark suite
3. Set up test coverage reporting
4. Ensure 100% production readiness

## Day-by-Day Plan

### Day 1: Fix RateLimiter Tests (Morning)
- [ ] **Make bucket_key/1 function public** in RateLimiter module:
  ```elixir
  # Change from defp to def
  def bucket_key(%{url: url, options: options}) do
    # existing implementation
  end
  ```
- [ ] **Fix all RateLimiter test failures** (~40 tests):
  - [ ] Update test access to use public function
  - [ ] Verify rate limiting logic still works
  - [ ] Run RateLimiter tests in isolation
- [ ] **Document rate limiter behavior** for future reference

### Day 1: Fix Remaining Test Failures (Afternoon)
- [ ] **Fix remaining ~40 test failures**:
  - [ ] Group failures by type
  - [ ] Fix GenServer.call timeout issues
  - [ ] Update mock configurations
  - [ ] Handle :noproc errors in tests
- [ ] **Run full test suite** to verify all tests pass
- [ ] **Commit fixes** with clear messages

### Day 2: Set Up Test Coverage (Morning)
- [ ] **Add ExCoveralls to dependencies**:
  ```elixir
  # mix.exs
  defp deps do
    [
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end
  ```
- [ ] **Configure coverage in mix.exs**:
  ```elixir
  def project do
    [
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end
  ```
- [ ] **Run coverage analysis**:
  ```bash
  mix coveralls.html
  ```
- [ ] **Document coverage metrics** in README

### Day 2: Create Benchmark Suite (Afternoon)
- [ ] **Add Benchfella dependency**:
  ```elixir
  {:benchfella, "~> 0.3", only: :dev}
  ```
- [ ] **Create benchmark directory structure**:
  ```
  benchmarks/
  ├── cache_bench.exs
  ├── http_bench.exs
  ├── notification_bench.exs
  └── pipeline_bench.exs
  ```

### Day 3: Implement Core Benchmarks
- [ ] **Cache Operations Benchmark** (`benchmarks/cache_bench.exs`):
  ```elixir
  defmodule CacheBench do
    use Benchfella
    alias WandererNotifier.Infrastructure.Cache
    
    @character_id 123456
    
    setup_all do
      # Warm cache with test data
      Cache.put_character(@character_id, %{name: "Test Character"})
    end
    
    bench "cache get character" do
      Cache.get_character(@character_id)
    end
    
    bench "cache put character" do
      Cache.put_character(@character_id, %{name: "Test Character"})
    end
    
    bench "cache key generation" do
      Cache.Keys.character(@character_id)
    end
  end
  ```

- [ ] **HTTP Client Benchmark** (`benchmarks/http_bench.exs`):
  ```elixir
  defmodule HttpBench do
    use Benchfella
    alias WandererNotifier.Infrastructure.Http
    
    bench "http client with ESI config" do
      # Mock response for benchmarking
      Http.get("https://esi.example.com/test", [], service: :esi)
    end
    
    bench "http client with retry logic" do
      Http.get("https://api.example.com/test", [], 
        retry_count: 3, 
        timeout: 5000
      )
    end
  end
  ```

- [ ] **Notification Flow Benchmark** (`benchmarks/notification_bench.exs`):
  ```elixir
  defmodule NotificationBench do
    use Benchfella
    alias WandererNotifier.Domains.Notifications.NotificationService
    
    @test_notification %{
      type: :kill_notification,
      data: %{killmail: %{killmail_id: 123}}
    }
    
    bench "notification processing" do
      NotificationService.send(@test_notification)
    end
  end
  ```

### Day 4: Performance Validation & Optimization
- [ ] **Run all benchmarks**:
  ```bash
  mix bench
  ```
- [ ] **Document baseline metrics**:
  - [ ] Cache operations: target < 1ms
  - [ ] HTTP requests: target < 100ms (mocked)
  - [ ] Notification processing: target < 10ms
  - [ ] Memory usage per operation

- [ ] **Identify performance bottlenecks** (if any):
  - [ ] Profile hot paths with :fprof
  - [ ] Check for N+1 queries
  - [ ] Verify efficient cache usage

- [ ] **Optimize if needed**:
  - [ ] Add strategic caching
  - [ ] Optimize database queries
  - [ ] Reduce unnecessary computations

### Day 5: Final Integration & Documentation
- [ ] **Run complete test suite with coverage**:
  ```bash
  mix coveralls.html
  ```
  - [ ] Verify 100% tests passing
  - [ ] Confirm 70%+ coverage achieved
  - [ ] Document any uncovered code

- [ ] **Run performance benchmark suite**:
  ```bash
  mix bench
  ```
  - [ ] Compare with targets
  - [ ] Document results in PERFORMANCE.md

- [ ] **Update documentation**:
  - [ ] **README.md**: Add coverage badge and benchmark results
  - [ ] **ARCHITECTURE.md**: Document final architecture
  - [ ] **PERFORMANCE.md**: Create with benchmark results
  - [ ] **CHANGELOG.md**: Document all refactoring changes

- [ ] **Create final release candidate**:
  ```bash
  mix release
  ```

## Success Criteria

### Required for Completion
- [ ] **100% test suite passing** (0 failures from 533 tests)
- [ ] **Test coverage ≥ 70%** with reporting configured
- [ ] **Performance benchmarks** created and documented
- [ ] **All documentation** updated
- [ ] **Release candidate** built successfully

### Quality Metrics
- **Test Health**: 533/533 passing (100%)
- **Coverage**: ≥ 70% (measured by ExCoveralls)
- **Cache Performance**: < 1ms per operation
- **HTTP Performance**: < 100ms (mocked)
- **Build Time**: < 30 seconds
- **Memory Usage**: Stable under load

## Definition of Done

- [ ] All tests passing (100%)
- [ ] Coverage reporting configured and ≥ 70%
- [ ] Benchmark suite created with 4+ benchmarks
- [ ] Performance baseline documented
- [ ] No compilation warnings
- [ ] Documentation fully updated
- [ ] Release candidate tested
- [ ] Code review completed
- [ ] PR merged to main branch

## Risk Management

### Low Risk Items
- Test fixes are straightforward (mostly access issues)
- Coverage setup is standard Elixir tooling
- Benchmarks don't affect production code

### Mitigation Strategies
1. Fix tests incrementally, verify after each batch
2. Use established tools (ExCoveralls, Benchfella)
3. Mock external services in benchmarks
4. Keep changes minimal and focused

## Post-Sprint Actions

1. **Deploy to staging** for final validation
2. **Run load tests** with production-like data
3. **Monitor performance** metrics
4. **Plan production rollout**
5. **Create maintenance runbook**

## Notes

This sprint represents the final 5% of work needed to achieve 100% production readiness. The focus is on quality assurance and performance validation rather than new features or major changes. With these tasks complete, the refactoring initiative will be fully successful and the system ready for production deployment.