import type { CronConfig } from "./render-crontab";

const cronConfig: CronConfig = {
  jobs: [
    {
      name: "healthcheck",
      schedule: "*/5 * * * *",
      enabled: true,
      command: "cd /app && pnpm hardhat healthcheck",
    },
    {
      name: "mainnet_auto_request_withdraw",
      schedule: "5 */3 * * *",
      enabled: false,
      command: "cd /app && pnpm hardhat autoRequestWithdraw --network mainnet",
    },
    {
      name: "mainnet_auto_claim_withdraw",
      schedule: "20 */3 * * *",
      enabled: false,
      command: "cd /app && pnpm hardhat autoClaimWithdraw --network mainnet",
    },
    {
      name: "mainnet_auto_request_lido_withdraw",
      schedule: "29,58 12-23,0-8 * * *",
      enabled: false,
      command:
        "cd /app && pnpm hardhat autoRequestLidoWithdraw --network mainnet",
    },
    {
      name: "mainnet_auto_claim_lido_withdraw",
      schedule: "32 0,12 * * *",
      enabled: false,
      command:
        "cd /app && pnpm hardhat autoClaimLidoWithdraw --network mainnet",
    },
    {
      name: "mainnet_auto_request_etherfi_withdraw",
      schedule: "10,40 * * * *",
      enabled: false,
      command:
        "cd /app && pnpm hardhat autoRequestEtherFiWithdraw --network mainnet",
    },
    {
      name: "mainnet_auto_claim_etherfi_withdraw",
      schedule: "40 * * * *",
      enabled: false,
      command:
        "cd /app && pnpm hardhat autoClaimEtherFiWithdraw --network mainnet",
    },
    {
      name: "mainnet_auto_request_ethena_withdraw",
      schedule: "12 * * * *",
      enabled: false,
      command:
        "cd /app && pnpm hardhat autoRequestEthenaWithdraw --network mainnet",
    },
    {
      name: "mainnet_auto_claim_ethena_withdraw",
      schedule: "40 * * * *",
      enabled: false,
      command:
        "cd /app && pnpm hardhat autoClaimEthenaWithdraw --network mainnet",
    },
    {
      name: "mainnet_collect_oeth_fees",
      schedule: "3 0 * * *",
      enabled: false,
      command: "cd /app && pnpm hardhat collectOETHFees --network mainnet",
    },
    {
      name: "mainnet_collect_lido_fees",
      schedule: "30 12 * * *",
      enabled: false,
      command: "cd /app && pnpm hardhat collectLidoFees --network mainnet",
    },
    {
      name: "mainnet_collect_etherfi_fees",
      schedule: "45 23 * * *",
      enabled: false,
      command: "cd /app && pnpm hardhat collectEtherFiFees --network mainnet",
    },
    {
      name: "mainnet_collect_ethena_fees",
      schedule: "45 23 * * *",
      enabled: false,
      command: "cd /app && pnpm hardhat collectEthenaFees --network mainnet",
    },
    {
      name: "mainnet_allocate_oeth",
      schedule: "42 * * * *",
      enabled: false,
      command: "cd /app && pnpm hardhat allocateOETH --network mainnet",
    },
    {
      name: "mainnet_allocate_lido",
      schedule: "38,08 * * * *",
      enabled: false,
      command: "cd /app && pnpm hardhat allocateLido --network mainnet",
    },
    {
      name: "mainnet_allocate_etherfi",
      schedule: "52 * * * *",
      enabled: false,
      command: "cd /app && pnpm hardhat allocateEtherFi --network mainnet",
    },
    {
      name: "mainnet_allocate_ethena",
      schedule: "28 * * * *",
      enabled: false,
      command: "cd /app && pnpm hardhat allocateEthena --network mainnet",
    },
    {
      name: "mainnet_set_prices_oeth",
      schedule: "*/10 * * * *",
      enabled: false,
      command: "cd /app && pnpm hardhat setPricesOETH --network mainnet",
    },
    {
      name: "mainnet_set_prices_lido",
      schedule: "*/30 * * * *",
      enabled: false,
      command: "cd /app && pnpm hardhat setPricesLido --network mainnet",
    },
    {
      name: "mainnet_set_prices_etherfi",
      schedule: "2,32 * * * *",
      enabled: false,
      command: "cd /app && pnpm hardhat setPricesEtherFi --network mainnet",
    },
    {
      name: "mainnet_set_prices_ethena",
      schedule: "4 * * * *",
      enabled: false,
      command: "cd /app && pnpm hardhat setPricesEthena --network mainnet",
    },
    {
      name: "sonic_auto_request_withdraw",
      schedule: "48,18 * * * *",
      enabled: false,
      command:
        "cd /app && pnpm hardhat autoRequestWithdrawSonic --network sonic",
    },
    {
      name: "sonic_auto_claim_withdraw",
      schedule: "58 */2 * * *",
      enabled: false,
      command: "cd /app && pnpm hardhat autoClaimWithdrawSonic --network sonic",
    },
    {
      name: "sonic_collect_fees",
      schedule: "55 23 * * *",
      enabled: false,
      command: "cd /app && pnpm hardhat collectFeesSonic --network sonic",
    },
    {
      name: "sonic_allocate",
      schedule: "1,31 * * * *",
      enabled: false,
      command: "cd /app && pnpm hardhat allocateSonic --network sonic",
    },
    {
      name: "os_silo_set_prices",
      schedule: "*/30 * * * *",
      enabled: false,
      command: "cd /app && pnpm hardhat setOSSiloPriceAction --network sonic",
    },
    {
      name: "sonic_collect_rewards",
      schedule: "45 23 * * *",
      enabled: false,
      command: "cd /app && pnpm hardhat collectRewardsSonic --network sonic",
    },
  ],
};

export default cronConfig;
