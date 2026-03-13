1. Tree-sitter Injection Test

    This document tests verbatim block injection highlighting.

    A Python example:
        def greet(name):
            print(f"Hello, {name}!")
        greet("world")
    :: python ::

    A JSON example:
        {
            "key": "value",
            "number": 42
        }
    :: json ::

    A plain verbatim block:
        This is just plain text
        in a verbatim block.
    :: note ::

    A grouped verbatim block (multiple subjects sharing one annotation):
    Install:
        $ brew install lex
    Run:
        $ lex help
    :: bash ::
