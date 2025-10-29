/// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Mainnet} from "contracts/utils/Addresses.sol";
// Test
import {Fork_Shared_Test} from "test/fork/Abstract4626MarketWrapper/shared/Shared.sol";

contract Fork_Concrete_MorphoMarket_MerkleClaim_Test_ is Fork_Shared_Test {
    function test_merkleClaim() public {
        uint256 amount = 1225.71332093851063813 ether;

        // Merkle proofs for the above claim, it should work for block 23_681_964
        bytes32[] memory proofs = new bytes32[](18);
        proofs[0] = 0x2eba1f3f30baa9770d22753e3efa56c682040788e9654724a9e68e16bec0e697;
        proofs[1] = 0xb10a5bd2da7b83b24226f272ec5fe01f72d8f1d463d7050671cfd91e412890f1;
        proofs[2] = 0x34a664fb2883cc32b8ee2aefc6009a0256bc42dc035a7fad2763f04499182854;
        proofs[3] = 0xa867ed9645a7a6f33d147602f1aabeed3848f34911ce9341d4af474d17844a1d;
        proofs[4] = 0xeb66d106ad3f677db4523ca3d1908aa9278b3104eb4714844313c2f5b36817c9;
        proofs[5] = 0xb07cb3e856141bce014c3a7ffbe10585afaa790472af682155acf617e8f284be;
        proofs[6] = 0x45591953cd7445b27d988408837bb50baa7185e6046542800f8fab340e18fc5a;
        proofs[7] = 0x09a14425a341ead75e2b03a0e1074bfdbbfcee98c349dd8a05ed3ecf9a125d63;
        proofs[8] = 0xc9273e4d94b41b3d937781f4b3760de2a6ed492b2d0fbaa2f928dafef65fe29a;
        proofs[9] = 0x87c6404ae1dce0a88b80f9c0024a4d05a3c1d6a07032600ca98b0c3d4c6d5c14;
        proofs[10] = 0x150327de4955b120e1bc04e2ca5808ec61077e31ed07cb30ad7cc3afb642487c;
        proofs[11] = 0x57442d37e2a3e2a3156770a22c9a133a7adf5ee3b2e4c1e950cd98ff3fede746;
        proofs[12] = 0x813f977612c1ee0daf967930bfa889789a6fef6a13f0564a93d08eb7b7170747;
        proofs[13] = 0x8448cd00a70cdba2cdbb38d4f2519b7beca1be3d52d32d94cb2fe3262f652576;
        proofs[14] = 0xb476316849ba78aedaebbb64f4558b2088db0a5ab75d5d966ed849557f2df66e;
        proofs[15] = 0x45600699ab71fa35ed7959d9b9477312ae881f33eea8950147db1011c3004b72;
        proofs[16] = 0x7a5e2311da57eac19dd34822de9088140335808171c91fbd84ed78f563f7a11d;
        proofs[17] = 0x5a6daa8cdee70d08054ba54c2c2ed2251fbc28f05f4fac9c7406e1f7e7fc3f75;

        // Get balance before claim
        uint256 balanceBefore = morpho.balanceOf(address(morphoMarket));

        // Main call to test
        morphoMarket.merkleClaim(Mainnet.MORPHO, amount, proofs);

        // Check balance after claim
        uint256 balanceAfter = morpho.balanceOf(address(morphoMarket));

        // Check that the balance has increased by the claimed amount
        assertEq(balanceAfter, balanceBefore + amount, "Incorrect MORPHO balance after claim");
    }
}
