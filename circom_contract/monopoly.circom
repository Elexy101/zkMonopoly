pragma circom 2.0.0;

include "circomlib-master/circuits/comparators.circom";  // Automatically includes the comparators template from node_modules

template SufficientFunds() {
    signal input funds; // Private input: player's total funds in wei
    signal input nextRequiredSMONO; // Private input: current required SMONO in wei 
    signal input xmonoPoints; // Private input: player's current XMONO-Points
    signal output isSufficient; // Output: 1 if funds >= nextRequiredSMONO, 0 otherwise

    // Define base SMONO unit: 1 SMONO = 10^18 wei
    var SMONO_UNIT = 1000000000000000000; // 10^18
    var BASE_THRESHOLD = 1000; // Initial threshold in SMONO units (1000 SMONO)

    // Verify nextRequiredSMONO matches expected formula: 1000 + 1000 * xmonoPoints (in SMONO units)
    signal expectedThreshold;
    expectedThreshold <== (BASE_THRESHOLD + xmonoPoints * 1000) * SMONO_UNIT;
    nextRequiredSMONO === expectedThreshold; // Constraint: ensure input threshold is correct

    // Use Circomlib's GreaterEqThan with 252 bits
    component geq = GreaterEqThan(252); // Changed from 256 to 252
    geq.in[0] <== funds;
    geq.in[1] <== nextRequiredSMONO;
    isSufficient <== geq.out;
}

component main { public [nextRequiredSMONO, xmonoPoints] } = SufficientFunds();
