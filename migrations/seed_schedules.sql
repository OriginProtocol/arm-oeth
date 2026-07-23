-- migrations/seed_schedules.sql
-- Apply against the shared automaton Postgres.
-- Commands match the original cron/cron-jobs.ts; the container's runContainer
-- spawns them via sh -c in workdir /app.

-- Remove schedules for the superseded USD ARM and the per-ARM pause actions.
-- Their USDC and shared-action replacements are inserted below.
DELETE FROM schedules
WHERE product = 'arm-oeth'
  AND name IN (
    'mainnet_auto_request_usd_withdraw',
    'mainnet_auto_claim_usd_withdraw',
    'mainnet_collect_usd_fees',
    'mainnet_allocate_usd',
    'mainnet_set_prices_usd',
    'mainnet_pause_usd',
    'mainnet_pause_lido',
    'mainnet_pause_etherfi',
    'mainnet_pause_ethena',
    'mainnet_pause_usdc'
  );

INSERT INTO schedules (product, name, command, cron_expr, timezone, enabled, note) VALUES
('arm-oeth', 'healthcheck',                          'cd /app && pnpm hardhat healthcheck',                                       '*/5 * * * *',           'UTC', false, NULL),
('arm-oeth', 'mainnet_auto_request_lido_withdraw',   'cd /app && pnpm hardhat autoRequestLidoWithdraw --network mainnet',         '29,58 12-23,0-8 * * *', 'UTC', false, NULL),
('arm-oeth', 'mainnet_auto_claim_lido_withdraw',     'cd /app && pnpm hardhat autoClaimLidoWithdraw --network mainnet',           '32 0,12 * * *',         'UTC', false, NULL),
('arm-oeth', 'mainnet_auto_request_etherfi_withdraw','cd /app && pnpm hardhat autoRequestEtherFiWithdraw --network mainnet',      '10,40 * * * *',         'UTC', false, NULL),
('arm-oeth', 'mainnet_auto_claim_etherfi_withdraw',  'cd /app && pnpm hardhat autoClaimEtherFiWithdraw --network mainnet',        '40 * * * *',            'UTC', false, NULL),
('arm-oeth', 'mainnet_auto_request_ethena_withdraw', 'cd /app && pnpm hardhat autoRequestEthenaWithdraw --network mainnet',       '12 * * * *',            'UTC', false, NULL),
('arm-oeth', 'mainnet_auto_claim_ethena_withdraw',   'cd /app && pnpm hardhat autoClaimEthenaWithdraw --network mainnet',         '40 * * * *',            'UTC', false, NULL),
('arm-oeth', 'mainnet_auto_request_usdc_withdraw',   'cd /app && pnpm hardhat autoRequestUSDCWithdraw --network mainnet',         '14 * * * *',            'UTC', false, NULL),
('arm-oeth', 'mainnet_auto_claim_usdc_withdraw',     'cd /app && pnpm hardhat autoClaimUSDCWithdraw --network mainnet',           '44 * * * *',            'UTC', false, NULL),
('arm-oeth', 'mainnet_collect_lido_fees',            'cd /app && pnpm hardhat collectLidoFees --network mainnet',                 '30 12 * * *',           'UTC', false, NULL),
('arm-oeth', 'mainnet_collect_etherfi_fees',         'cd /app && pnpm hardhat collectEtherFiFees --network mainnet',              '45 23 * * *',           'UTC', false, NULL),
('arm-oeth', 'mainnet_collect_ethena_fees',          'cd /app && pnpm hardhat collectEthenaFees --network mainnet',               '45 23 * * *',           'UTC', false, NULL),
('arm-oeth', 'mainnet_collect_usdc_fees',            'cd /app && pnpm hardhat collectUSDCFees --network mainnet',                 '50 23 * * *',           'UTC', false, NULL),
('arm-oeth', 'mainnet_allocate_lido',                'cd /app && pnpm hardhat allocateLido --network mainnet',                    '38,08 * * * *',         'UTC', false, NULL),
('arm-oeth', 'mainnet_allocate_etherfi',             'cd /app && pnpm hardhat allocateEtherFi --network mainnet',                 '52 * * * *',            'UTC', false, NULL),
('arm-oeth', 'mainnet_allocate_ethena',              'cd /app && pnpm hardhat allocateEthena --network mainnet',                  '28 * * * *',            'UTC', false, NULL),
('arm-oeth', 'mainnet_allocate_usdc',                'cd /app && pnpm hardhat allocateUSDC --network mainnet',                    '26 * * * *',            'UTC', false, NULL),
('arm-oeth', 'mainnet_set_prices_lido',              'cd /app && pnpm hardhat setPricesLido --network mainnet',                   '*/30 * * * *',          'UTC', false, NULL),
('arm-oeth', 'mainnet_set_prices_etherfi',           'cd /app && pnpm hardhat setPricesEtherFi --network mainnet',                '2,32 * * * *',          'UTC', false, NULL),
('arm-oeth', 'mainnet_set_prices_ethena',            'cd /app && pnpm hardhat setPricesEthena --network mainnet',                 '4 * * * *',             'UTC', false, NULL),
('arm-oeth', 'mainnet_set_prices_usdc',              'cd /app && pnpm hardhat setPricesUSDC --network mainnet',                   '6 * * * *',             'UTC', false, NULL),
-- Emergency pause action: manual-only (enabled=false). Edit `--arm` before
-- using "Run now". The supported Ethereum ARMs are lido, etherfi, ethena,
-- oeth, and usdc. cron_expr is a placeholder and never fires while disabled.
('arm-oeth', 'Pause ARM - Mainnet',                  'cd /app && pnpm hardhat pause --arm lido --network mainnet',                 '0 0 * * *',             'UTC', false, NULL),
-- LP redeem claims on behalf of users: manual-only (enabled=false). The runner
-- dispatches `command` verbatim, so the required `--arm` and `--ids` flags must
-- be set before running, by editing this row's command. `lido` and `0` below are
-- placeholders. For ids, use a comma-separated list, eg --ids 12,13,14.
-- cron_expr is a placeholder that never fires while disabled.
('arm-oeth', 'mainnet_claim_redeem',                 'cd /app && pnpm hardhat claimRedeem --arm lido --ids 0 --network mainnet',         '0 0 * * *',             'UTC', false, NULL),
-- ARM buffer changes: manual-only (enabled=false). Edit `--arm` and `--buffer`
-- before using "Run now". 0.1 = 10% buffer, 1 = 100% buffer.
('arm-oeth', 'Set ARM Buffer - Mainnet',             'cd /app && pnpm hardhat setARMBufferAction --arm lido --buffer 0.1 --network mainnet', '0 0 * * *',          'UTC', false, NULL),
-- ARM cap changes: manual-only (enabled=false). Edit `--arm`, `--accounts`,
-- and/or `--cap` before using "Run now".
('arm-oeth', 'Set Liquidity Provider Caps - Mainnet','cd /app && pnpm hardhat setLiquidityProviderCapsAction --arm lido --accounts 0x0000000000000000000000000000000000000000 --cap 20000 --network mainnet', '0 0 * * *', 'UTC', false, NULL),
('arm-oeth', 'Set Total Assets Cap - Mainnet',       'cd /app && pnpm hardhat setTotalAssetsCapAction --arm lido --cap 100000 --network mainnet', '0 0 * * *',         'UTC', false, NULL),
('arm-oeth', 'sonic_auto_request_withdraw',          'cd /app && pnpm hardhat autoRequestWithdrawSonic --network sonic',          '48,18 * * * *',         'UTC', false, NULL),
('arm-oeth', 'sonic_auto_claim_withdraw',            'cd /app && pnpm hardhat autoClaimWithdrawSonic --network sonic',            '10 * * * *',            'UTC', false, NULL),
('arm-oeth', 'sonic_collect_fees',                   'cd /app && pnpm hardhat collectFeesSonic --network sonic',                  '55 23 * * *',           'UTC', false, NULL),
('arm-oeth', 'sonic_allocate',                       'cd /app && pnpm hardhat allocateSonic --network sonic',                     '1,31 * * * *',          'UTC', false, NULL),
('arm-oeth', 'os_silo_set_prices',                   'cd /app && pnpm hardhat setOSSiloPriceAction --network sonic',              '*/30 * * * *',          'UTC', false, NULL),
('arm-oeth', 'sonic_collect_rewards',                'cd /app && pnpm hardhat collectRewardsSonic --network sonic',               '45 23 * * *',           'UTC', false, NULL)
ON CONFLICT (product, name) DO NOTHING;
