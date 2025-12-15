const axios = require("axios");

const MERKL_API_ENDPOINT = "https://api.merkl.xyz/v4";

const getMerklRewards = async ({ userAddress, chainId = 1 }) => {
  const url = `${MERKL_API_ENDPOINT}/users/${userAddress}/rewards?chainId=${chainId}`;
  try {
    const response = await axios.get(url);

    return {
      amount: response.data[0].rewards[0].amount,
      token: response.data[0].rewards[0].token.address,
      proofs: response.data[0].rewards[0].proofs,
    };
  } catch (err) {
    if (err.response) {
      console.error("Response data  : ", err.response.data);
      console.error("Response status: ", err.response.status);
      console.error("Response status: ", err.response.statusText);
    }
    throw Error(`Call to Merkl API failed: ${err.message}`);
  }
};

module.exports = { getMerklRewards };
