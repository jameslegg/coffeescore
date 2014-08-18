all: coffeescore.js

run: all
	nodejs coffeescore.js

%.js: %.coffee
	coffee -bc $<

clean:
	rm *.js || true
