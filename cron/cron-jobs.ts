import type { CronConfig } from "./render-crontab";

const cronConfig: CronConfig = {
  jobs: [
    {
      name: "healthcheck",
      schedule: "*/5 * * * *",
      enabled: true,
      command: "cd /app && npx hardhat healthcheck",
    },
    {
      name: "mainnet_auto_request_withdraw",
      schedule: "5 */3 * * *",
      enabled: false,
      command: "cd /app && npx hardhat autoRequestWithdraw --network mainnet",
    },
    {
      name: "mainnet_auto_claim_withdraw",
      schedule: "20 */3 * * *",
      enabled: false,
      command: "cd /app && npx hardhat autoClaimWithdraw --network mainnet",
    },
    {
      name: "mainnet_auto_request_lido_withdraw",
      schedule: "29,58 12-23,0-8 * * *",
      enabled: true,
      command:
        "cd /app && npx hardhat autoRequestLidoWithdraw --network mainnet",
    },
    {
      name: "mainnet_auto_claim_lido_withdraw",
      schedule: "32 0,12 * * *",
      enabled: true,
      command:
        "cd /app && npx hardhat autoClaimLidoWithdraw --network mainnet",
    },
    {
      name: "mainnet_auto_request_etherfi_withdraw",
      schedule: "10,40 * * * *",
      enabled: true,
      command:
        "cd /app && npx hardhat autoRequestEtherFiWithdraw --network mainnet",
    },
    {
      name: "mainnet_auto_claim_etherfi_withdraw",
      schedule: "40 * * * *",
      enabled: true,
      command:
        "cd /app && npx hardhat autoClaimEtherFiWithdraw --network mainnet",
    },
    {
      name: "mainnet_auto_request_ethena_withdraw",
      schedule: "0 */3 * * *",
      enabled: true,
      command:
        "cd /app && npx hardhat autoRequestEthenaWithdraw --network mainnet",
    },
    {
      name: "mainnet_auto_claim_ethena_withdraw",
      schedule: "40 * * * *",
      enabled: true,
      command:
        "cd /app && npx hardhat autoClaimEthenaWithdraw --network mainnet",
    },
    {
      name: "mainnet_collect_oeth_fees",
      schedule: "3 0 * * *",
      enabled: false,
      command: "cd /app && npx hardhat collectOETHFees --network mainnet",
    },
    {
      name: "mainnet_collect_lido_fees",
      schedule: "30 12 * * *",
      enabled: true,
      command: "cd /app && npx hardhat collectLidoFees --network mainnet",
    },
    {
      name: "mainnet_collect_etherfi_fees",
      schedule: "45 23 * * *",
      enabled: true,
      command: "cd /app && npx hardhat collectEtherFiFees --network mainnet",
    },
    {
      name: "mainnet_collect_ethena_fees",
      schedule: "45 23 * * *",
      enabled: true,
      command: "cd /app && npx hardhat collectEthenaFees --network mainnet",
    },
    {
      name: "mainnet_allocate_oeth",
      schedule: "42 * * * *",
      enabled: false,
      command: "cd /app && npx hardhat allocateOETH --network mainnet",
    },
    {
      name: "mainnet_allocate_lido",
      schedule: "38,08 * * * *",
      enabled: true,
      command: "cd /app && npx hardhat allocateLido --network mainnet",
    },
    {
      name: "mainnet_allocate_etherfi",
      schedule: "52 * * * *",
      enabled: false,
      command: "cd /app && npx hardhat allocateEtherFi --network mainnet",
    },
    {
      name: "mainnet_allocate_ethena",
      schedule: "28 * * * *",
      enabled: true,
      command: "cd /app && npx hardhat allocateEthena --network mainnet",
    },
    {
      name: "mainnet_set_prices_oeth",
      schedule: "*/10 * * * *",
      enabled: false,
      command: "cd /app && npx hardhat setPricesOETH --network mainnet",
    },
    {
      name: "mainnet_set_prices_lido",
      schedule: "*/30 * * * *",
      enabled: true,
      command: "cd /app && npx hardhat setPricesLido --network mainnet",
    },
    {
      name: "mainnet_set_prices_etherfi",
      schedule: "2,32 * * * *",
      enabled: true,
      command: "cd /app && npx hardhat setPricesEtherFi --network mainnet",
    },
    {
      name: "mainnet_set_prices_ethena",
      schedule: "0 * * * *",
      enabled: true,
      command: "cd /app && npx hardhat setPricesEthena --network mainnet",
    },
    {
      name: "sonic_auto_request_withdraw",
      schedule: "48,18 * * * *",
      enabled: true,
      command:
        "cd /app && npx hardhat autoRequestWithdrawSonic --network sonic",
    },
    {
      name: "sonic_auto_claim_withdraw",
      schedule: "58 */2 * * *",
      enabled: true,
      command: "cd /app && npx hardhat autoClaimWithdrawSonic --network sonic",
    },
    {
      name: "sonic_collect_fees",
      schedule: "55 23 * * *",
      enabled: true,
      command: "cd /app && npx hardhat collectFeesSonic --network sonic",
    },
    {
      name: "sonic_allocate",
      schedule: "1,31 * * * *",
      enabled: true,
      command: "cd /app && npx hardhat allocateSonic --network sonic",
    },
    {
      name: "sonic_set_prices",
      schedule: "*/30 * * * *",
      enabled: true,
      command: "cd /app && npx hardhat setPricesSonic --network sonic",
    },
    {
      name: "sonic_collect_rewards",
      schedule: "45 23 * * *",
      enabled: true,
      command: "cd /app && npx hardhat collectRewardsSonic --network sonic",
    },
  ],
};

export default cronConfig;
