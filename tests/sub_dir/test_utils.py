from pycharm_bug.utils import add_value

def test_add_value():
    assert add_value(1, added= 1) == 2


def test_add_value_conftest_loaded():
    assert add_value(1) == 11
