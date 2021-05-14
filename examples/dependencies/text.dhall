let deps = ./dependencies.dhall

in "${deps.a.greeting}, ${deps.b.subject}!"
