# Cross-chain Rebase Token

1. A protocol that allows users to deposit into a vault and in return, receive rebase token that represent their underlying balance.
2. Rebase token -> balanceOf function is dynamic to show the changing balance with time.
   1. Balance increases linearly with time.
   2. mint tokens to users every time they perform an action(minting, burning, transferring, or bridging).
3. Interest rate 
   1. individually set an interest rate for each user based on some global interest rate of the protocol at the time the user deposits into the vault.
   2. This global interest rate can only decrease to incentivise early adopters.
   3. Increase token adoption.