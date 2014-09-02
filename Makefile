NODE = nodejs
NPM = npm
DEPS = node_modules/sqlite3

all: $(DEPS) coffeescore.js

node_modules/%:
	$(NPM) install

run: all
	$(NODE) coffeescore.js

%.js: %.coffee
	coffee -bc $<

clean:
	rm *.js || true

realclean: clean
	rm -r $(DEPS)
