-- migrations/seed_schedules.sql
-- Apply against the shared automaton Postgres.
-- Commands match the original cron/cron-jobs.ts; the container's runContainer
-- spawns them via sh -c in workdir /app.

INSERT INTO schedules (product, name, command, cron_expr, timezone, enabled, note) VALUES
('arm-oeth', 'healthcheck',                          'cd /app && pnpm hardhat healthcheck',                                       '*/5 * * * *',           'UTC', true,  NULL),
('arm-oeth', 'mainnet_auto_request_lido_withdraw',   'cd /app && pnpm hardhat autoRequestLidoWithdraw --network mainnet',         '29,58 12-23,0-8 * * *', 'UTC', false, NULL),
('arm-oeth', 'mainnet_auto_claim_lido_withdraw',     'cd /app && pnpm hardhat autoClaimLidoWithdraw --network mainnet',           '32 0,12 * * *',         'UTC', false, NULL),
('arm-oeth', 'mainnet_auto_request_etherfi_withdraw','cd /app && pnpm hardhat autoRequestEtherFiWithdraw --network mainnet',      '10,40 * * * *',         'UTC', false, NULL),
('arm-oeth', 'mainnet_auto_claim_etherfi_withdraw',  'cd /app && pnpm hardhat autoClaimEtherFiWithdraw --network mainnet',        '40 * * * *',            'UTC', false, NULL),
('arm-oeth', 'mainnet_auto_request_ethena_withdraw', 'cd /app && pnpm hardhat autoRequestEthenaWithdraw --network mainnet',       '12 * * * *',            'UTC', false, NULL),
('arm-oeth', 'mainnet_auto_claim_ethena_withdraw',   'cd /app && pnpm hardhat autoClaimEthenaWithdraw --network mainnet',         '40 * * * *',            'UTC', false, NULL),
('arm-oeth', 'mainnet_collect_lido_fees',            'cd /app && pnpm hardhat collectLidoFees --network mainnet',                 '30 12 * * *',           'UTC', false, NULL),
('arm-oeth', 'mainnet_collect_etherfi_fees',         'cd /app && pnpm hardhat collectEtherFiFees --network mainnet',              '45 23 * * *',           'UTC', false, NULL),
('arm-oeth', 'mainnet_collect_ethena_fees',          'cd /app && pnpm hardhat collectEthenaFees --network mainnet',               '45 23 * * *',           'UTC', false, NULL),
('arm-oeth', 'mainnet_allocate_lido',                'cd /app && pnpm hardhat allocateLido --network mainnet',                    '38,08 * * * *',         'UTC', false, NULL),
('arm-oeth', 'mainnet_allocate_etherfi',             'cd /app && pnpm hardhat allocateEtherFi --network mainnet',                 '52 * * * *',            'UTC', false, NULL),
('arm-oeth', 'mainnet_allocate_ethena',              'cd /app && pnpm hardhat allocateEthena --network mainnet',                  '28 * * * *',            'UTC', false, NULL),
('arm-oeth', 'mainnet_set_prices_lido',              'cd /app && pnpm hardhat setPricesLido --network mainnet',                   '*/30 * * * *',          'UTC', false, NULL),
('arm-oeth', 'mainnet_set_prices_etherfi',           'cd /app && pnpm hardhat setPricesEtherFi --network mainnet',                '2,32 * * * *',          'UTC', false, NULL),
('arm-oeth', 'mainnet_set_prices_ethena',            'cd /app && pnpm hardhat setPricesEthena --network mainnet',                 '4 * * * *',             'UTC', false, NULL),
('arm-oeth', 'sonic_auto_request_withdraw',          'cd /app && pnpm hardhat autoRequestWithdrawSonic --network sonic',          '48,18 * * * *',         'UTC', false, NULL),
('arm-oeth', 'sonic_auto_claim_withdraw',            'cd /app && pnpm hardhat autoClaimWithdrawSonic --network sonic',            '10 * * * *',            'UTC', false, NULL),
('arm-oeth', 'sonic_collect_fees',                   'cd /app && pnpm hardhat collectFeesSonic --network sonic',                  '55 23 * * *',           'UTC', false, NULL),
('arm-oeth', 'sonic_allocate',                       'cd /app && pnpm hardhat allocateSonic --network sonic',                     '1,31 * * * *',          'UTC', false, NULL),
('arm-oeth', 'os_silo_set_prices',                   'cd /app && pnpm hardhat setOSSiloPriceAction --network sonic',              '*/30 * * * *',          'UTC', false, NULL),
('arm-oeth', 'sonic_collect_rewards',                'cd /app && pnpm hardhat collectRewardsSonic --network sonic',               '45 23 * * *',           'UTC', false, NULL)
ON CONFLICT DO NOTHING;
