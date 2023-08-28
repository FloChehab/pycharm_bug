from pycharm_bug.utils import add_value

add_value.__kwdefaults__ = {
    **add_value.__kwdefaults__,
    "added": 10,
}
