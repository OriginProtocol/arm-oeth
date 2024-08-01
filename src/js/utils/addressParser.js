const { parse } = require("@solidity-parser/parser");
const { readFileSync } = require("fs");

const log = require("./logger")("utils:addressParser");

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
  const libraryName = network.chainId === 1 ? "Mainnet" : "Holesky";
  const library = ast.children.find((node) => node.name === libraryName);

  if (!library) {
    throw new Error(
      `Failed to find library "${libraryName}" in file "${fileName}".`
    );
  }

  // Find the variable in the library
  const variable = library.subNodes.find(
    (node) => node.variables[0].name === name
  );

  if (!variable) {
    throw new Error(
      `Failed to find address variable ${name} in ${libraryName}.`
    );
  }

  log(
    `Found address ${variable.initialValue.number} for variable ${name} in ${libraryName}.`
  );

  return variable.initialValue.number;
};

module.exports = {
  parseAddress,
};
