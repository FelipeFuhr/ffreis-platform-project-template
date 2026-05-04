package main

import (
	"os"

	"github.com/ffreis/platform-project-template/cmd"
)

var execute = cmd.Execute
var exitFunc = os.Exit

func main() {
	exitFunc(execute())
}
