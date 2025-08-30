pragma circom 2.0.0;

template SufficientFunds() {
    signal input funds; // Private input: player's total funds in wei
    signal output isSufficient; // Output: 1 if funds >= 1000 SMONO, 0 otherwise

    // Define the threshold: 1000 SMONO in wei
    var SMONO_THRESHOLD = 1000000000000000000000; // 1000 SMONO = 10^18 * 1000 wei

    // Compute difference
    signal diff;
    diff <== funds - SMONO_THRESHOLD;

    // Use NonNegative template to check if diff >= 0
    component nonNegativeCheck = NonNegative(256); // Use 256 bits for sufficient range
    nonNegativeCheck.in <== diff;
    isSufficient <== nonNegativeCheck.out;
}

template NonNegative(n) {
    signal input in;
    signal output out;
    
    signal bits[n];
    var sum = 0;
    for (var i = 0; i < n; i++) {
        bits[i] <-- (in >> i) & 1;
        bits[i] * (1 - bits[i]) === 0; // Constraint: bits[i] is 0 or 1
        sum += bits[i] * (2 ** i);
    }
    sum === in; // Constraint: sum of bits reconstructs input
    out <== 1 - bits[n-1]; // If in >= 0, most significant bit is 0, so out = 1
}

component main = SufficientFunds();