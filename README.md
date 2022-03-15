# Badger OnChain GuestList Factory

BadgerDAO uses `guestlists` for guarded launches. These are simple contracts that ensure deposits cannot go above a certain threshold.

The process of deploying and setting `guestLists`, and setting all the values in one go.

The logic that calculates the want token values for each guestlist and converts it from Dollars to Want is added, making it easier for the developers to quickly set them up.

## Dev

- Copy `.env.exmaple` to `.env` and update the keys;
- [Install Brownie](https://eth-brownie.readthedocs.io/en/stable/install.html);
- `brownie test`.