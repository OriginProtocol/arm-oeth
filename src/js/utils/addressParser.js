const { parse } = require("@solidity-parser/parser");
const { readFileSync } = require("fs");

const log = require("./logger")("utils:addressParser");

const parseDeployedAddress = async (name) => {
  const network = await ethers.provider.getNetwork();
  const chainId = network.chainId;

  const fileName = `./build/deployments-${chainId}.json`;
  log(`Parsing deployed contract ${name} from ${fileName}.`);
  try {
    const data = readFileSync(fileName, "utf-8");

    // Parse the JSON data
    const deploymentData = JSON.parse(data);

    if (!deploymentData?.contracts[name]) {
      throw new Error(`Failed to find deployed address for ${name}.`);
    }

    return deploymentData.contracts[name];
  } catch (err) {
    throw new Error(
      `Failed to parse deployed contract "${name}" from "${fileName}".`,
      {
        cause: err,
      },
    );
  }
};

// Parse an address from the Solidity Addresses file
const parseAddress = async (name) => {
  // parse from Addresses.sol file
  const fileName = "./src/contracts/utils/Addresses.sol";
  let solidityCode;
  try {
    solidityCode = readFileSync(fileName, "utf8");
  } catch (err) {
    throw new Error(`Failed to read file "${fileName}".`, {
      cause: err,
    });
  }

  let ast;
  try {
    // Parse the solidity code into abstract syntax tree (AST)
    ast = parse(solidityCode, {});
  } catch (err) {
    throw new Error(`Failed to parse solidity code in file ${fileName}.`, {
      cause: err,
    });
  }

  // Find the library in the AST depending on the network chain id
  const network = await ethers.provider.getNetwork();
  const libraryName =
    network.chainId == 1
      ? "Mainnet"
      : network.chainId == 146
        ? "Sonic"
        : "Holesky";
  const library = ast.children.find((node) => node.name === libraryName);

  if (!library) {
    throw new Error(
      `Failed to find library "${libraryName}" in file "${fileName}".`,
    );
  }

  // Find the variable in the library
  const variable = library.subNodes.find(
    (node) => node.variables[0].name === name,
  );

  if (!variable) {
    throw new Error(
      `Failed to find address variable ${name} in ${libraryName}.`,
    );
  }

  log(
    `Found address ${variable.initialValue.number} for variable ${name} in ${libraryName}.`,
  );

  return variable.initialValue.number;
};

module.exports = {
  parseAddress,
  parseDeployedAddress,
};
