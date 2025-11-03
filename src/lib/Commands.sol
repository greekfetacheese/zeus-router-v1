// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

library Commands {
    bytes1 constant PERMIT2_PERMIT = 0x00;
    bytes1 constant V2_SWAP = 0x01;
    bytes1 constant V3_SWAP = 0x02;
    bytes1 constant V4_SWAP = 0x03;
    bytes1 constant WRAP_ETH = 0x04;
    bytes1 constant WRAP_ALL_ETH = 0x05;
    bytes1 constant UNWRAP_WETH = 0x06;
    bytes1 constant SWEEP = 0x07;
}
