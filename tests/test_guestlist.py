import brownie
from brownie import *

AddressZero = "0x0000000000000000000000000000000000000000"
MaxUint256 = str(int(2 ** 256 - 1))

## Test where you add a guestlist
def test_add_guestlist(gov, vault_one, want_one, want_one_rich, vault_one_gov,  guestlist):
    # Adding dev to guestlist
    guestlist.setGuests([want_one_rich], [True], {"from": gov})

    # Sets guestlist on Vault (Requires Vault's gov)
    vault_one.setGuestList(guestlist.address, {"from": vault_one_gov})

    depositAmount = 1e18

    # Deposit
    want_one.approve(vault_one, MaxUint256, {"from": want_one_rich})

    before_shares = want_one.balanceOf(vault_one)

    vault_one.deposit(depositAmount, {"from": want_one_rich})

    after_shares = want_one.balanceOf(vault_one)

    assert after_shares - before_shares == depositAmount

    # Deposit
    depositAmount_big = 1e20
    assert depositAmount_big <= want_one.balanceOf(want_one_rich)
    with brownie.reverts():
        vault_one.deposit(depositAmount_big, {"from": want_one_rich})
