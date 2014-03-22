# See the README for installation instructions.

# Utilities
JS_COMPILER = ./node_modules/uglify-js/bin/uglifyjs -c -m -
MARKDOWN_COMPILER = kramdown

# Turns out that just pointing Vows at a directory doesn't work, and its test matcher matches on
# the test's title, not its pathname. So we need to find everything in test/vows first.
VOWS = find test/vows -type f -name '*.js' -o -name '*.coffee' ! -name '.*' | xargs ./node_modules/.bin/vows --isolate --dot-matrix
MOCHA = find test/mocha -type f -name '*.js' -o -name '*.coffee' ! -name '.*' | xargs node_modules/.bin/mocha --reporter dot

SASS_COMPILER = sass -I src -I public -r ./src/helpers/sass/lab_fontface.rb
R_OPTIMIZER = ./node_modules/.bin/r.js

LAB_SRC_FILES := $(shell find src/lab -type f ! -name '.*' -print)
MD2D_SRC_FILES := $(shell find src/lab/models/md2d -type f ! -name '.*' -print)

GRAPHER_SRC_FILES := $(shell find src/lab/grapher -type f ! -name '.*' -print)
IMPORT_EXPORT_SRC_FILES := $(shell find src/lab/import-export -type f ! -name '.*' -print)
MML_CONVERTER_SRC_FILES := $(shell find src/lab/mml-converter -type f ! -name '.*' -print)

COMMON_SRC_FILES := $(shell find src/lab/common -type f ! -name '.*' -print)

# files generated by script during build process so cannot be listed using shell find.
COMMON_SRC_FILES += src/lab/lab.version.js

FONT_FOLDERS := $(shell find vendor/fonts -mindepth 1 -maxdepth 1)

SASS_LAB_LIBRARY_FILES := $(shell find src/sass/lab -name '*.sass')
SHUTTERBUG_GEM := $(shell bundle show shutterbug)

# targets

INTERACTIVE_FILES := $(shell find src/models src/interactives -name '*.json' -exec echo {} \; | sed s'/src\/\(.*\)/public\/\1/' )
vpath %.json src

HAML_FILES := $(shell find src -name '*.haml' -exec echo {} \; | sed s'/src\/\(.*\)\.haml/public\/\1/' )
vpath %.haml src

SASS_FILES := $(shell find src -name '*.sass' -and -not -path "src/sass/*" -exec echo {} \; | sed s'/src\/\(.*\)\.sass/public\/\1.css/' )
SASS_FILES += $(shell find src -name '*.scss' -and -not -path "src/sass/*" -exec echo {} \; | sed s'/src\/\(.*\)\.scss/public\/\1.css/' )
vpath %.sass src
vpath %.scss src

MARKDOWN_FILES := $(patsubst %.md, public/%.html, $(wildcard *.md))
DEV_MARKDOWN_FILES := $(patsubst %.md, public/%.html, $(wildcard developer-doc/*.md))

LAB_JS_FILES = \
	public/lab/lab.js \
	public/lab/lab.grapher.js \
	public/lab/lab.mml-converter.js \
	public/lab/lab.import-export.js

# default target executed when running make. Run the $(MAKE) public task rather than simply
# declaring a dependency on 'public' because 'bundle install' and 'npm install' might update some
# sources, and we want to recompute stale dependencies after that.
.PHONY: all
all: \
	vendor/d3/d3.js \
	node_modules
	$(MAKE) public

# clean, make ...
.PHONY: everything
everything:
	$(MAKE) clean
	$(MAKE) all

.PHONY: src
src: \
	$(MARKDOWN_FILES) \
	$(DEV_MARKDOWN_FILES) \
	$(LAB_JS_FILES) \
	$(LAB_JS_FILES:.js=.min.js) \
	$(HAML_FILES) \
	$(SASS_FILES) \
	$(INTERACTIVE_FILES) \
	public/embeddable.html \
	public/lab/lab.json

.PHONY: clean
clean:
	ruby script/check-development-dependencies.rb
	# remove the .bundle dir in case we are running this after running: make clean-for-tests
	# which creates a persistent bundle grouping after installing just the minimum
	# necessary set of gems for running tests using the arguments: --without development app
	# Would be nice if bundle install had a --withall option to cancel this persistence.
	rm -rf .bundle
	# install/update Ruby Gems
	bundle install
	mkdir -p public
	$(MAKE) clean-public
	rm -f src/lab/lab.version.js
	# Remove Node modules.
	rm -rf node_modules
	$(MAKE) prepare-submodules

# public dir cleanup.
.PHONY: clean-public
clean-public:
	bash -O extglob -c 'rm -rf public/!(.git|version)'

# versioned archives cleanup.
.PHONY: clean-archives
clean-archives:
	rm -rf version
	rm -rf public/version

.PHONY: prepare-submodules
prepare-submodules:
	-$(MAKE) submodule-update || $(MAKE) submodule-update-tags
	# Remove generated products in vendor libraries
	rm -f vendor/jquery/dist/jquery*.js
	rm -f vendor/jquery-ui/dist/jquery-ui*.js
	# hack to always download a new copy of grunt-contrib-jshint
	# because of packaging issues with an unresolved jshint depedency when
	# an older version of jshint is installed
	if [ -d vendor/jquery/node_modules/grunt-contrib-jshint ]; then rm -rf vendor/jquery/node_modules/grunt-contrib-jshint; fi
	if [ -d vendor/jquery-ui/node_modules/grunt-contrib-jshint ]; then rm -rf vendor/jquery-ui/node_modules/grunt-contrib-jshint; fi	

# ------------------------------------------------
#
#   Testing
#
# ------------------------------------------------

.PHONY: test
test: test/layout.html \
    node_modules/d3 \
    node_modules/arrays \
	public \
	$(LAB_JS_FILES) \
	$(JS_FILES:.js=.min.js)
	@echo
	@echo 'Mocha tests ...'
	@$(MOCHA)
	@echo 'Vows tests ...'
	@$(VOWS)
	@echo

# run vows test WITHOUT trying to build Lab JS first. Run 'make; make test-mocha' to build & test.
.PHONY: test-vows
test-vows:
	@echo 'Running Vows tests ...'
	@$(VOWS)

# run mocha test WITHOUT trying to build Lab JS first. Run 'make; make test-mocha' to build & test.
.PHONY: test-mocha
test-mocha:
	@echo 'Running Mocha tests ...'
	@$(MOCHA)

.PHONY: debug-mocha
debug-mocha:
	@echo 'Running Mocha tests in debug mode...'
	@$(MOCHA) --debug-brk

%.min.js: %.js
	@rm -f $@
ifndef LAB_DEVELOPMENT
	$(JS_COMPILER) < $< > $@
	@chmod ug+w $@
else
endif

.PHONY: public/test
public/test: public/embeddable-test-mocha.html
	mkdir -p public/test
	cp node_modules/mocha/mocha.js public/test
	cp node_modules/mocha/mocha.css public/test
	cp node_modules/chai/chai.js public/test
	cp test/test1.js public/test
	./node_modules/mocha-phantomjs/bin/mocha-phantomjs -R dot 'public/embeddable-test-mocha.html#interactives/samples/1-oil-and-water-shake.json'

# ------------------------------------------------
#
#   Submodules
#
# ------------------------------------------------

vendor/d3:
	submodule-update

.PHONY: submodule-update
submodule-update:
	git submodule update --init --recursive

.PHONY: submodule-update-tags
submodule-update-tags:
	git submodule sync
	git submodule foreach --recursive 'git fetch --tags'
	git submodule update --init --recursive

# ------------------------------------------------
#
#   Node modules
#
# ------------------------------------------------

node_modules: node_modules/d3 \
	node_modules/arrays
	npm install

node_modules/d3:
	npm install vendor/d3

node_modules/arrays:
	npm install src/modules/arrays

# ------------------------------------------------
#
#   public/
#
# ------------------------------------------------

public: \
	copy-resources-to-public \
	public/lab \
	public/lab/jars/lab-sensor-applet-interface-dist \
	public/lab/resources \
	public/vendor \
	public/developer-doc
	script/update-git-commit-and-branch.rb
	$(MAKE) src

# copy everything (including symbolic links) except files that are
# used to generate resources from src/ to public/
.PHONY: copy-resources-to-public
copy-resources-to-public:
	rsync -aq --exclude='helpers/' --exclude='layouts/' --exclude='modules/' --exclude='sass/' --exclude='vendor/' --exclude='lab/' --filter '+ */' --exclude='*.haml' --exclude='*.sass' --exclude='*.scss' --exclude='*.yaml' --exclude='*.coffee' --exclude='*.rb' --exclude='*.md' src/ public/

public/developer-doc:
	mkdir -p public/developer-doc

# ------------------------------------------------
#
#   public/lab
#
#   Generates the Lab Framework JavaScript resources
#
# ------------------------------------------------

public/lab:
	mkdir -p public/lab

public/lab/lab.json: \
	src/lab/common/controllers/interactive-metadata.js \
	src/lab/models/energy2d/metadata.js \
	src/lab/models/md2d/models/metadata.js \
	src/lab/models/sensor/metadata.js \
	src/lab/models/signal-generator/metadata.js \
	src/lab/models/iframe/metadata.js \
	src/lab/models/solar-system/models/metadata.js
	node src/helpers/lab.json.js

public/lab/lab.js: \
	$(LAB_SRC_FILES) \
	src/lab/lab.version.js
	$(R_OPTIMIZER) -o src/lab/lab.build.js

src/lab/lab.version.js: \
	script/generate-js-version.rb \
	src/lab/git-commit \
	src/lab/git-dirty \
	src/lab/git-branch-name
	./script/generate-js-version.rb

src/lab/git-commit:
	./script/update-git-commit-and-branch.rb

src/lab/git-branch-name:
	./script/update-git-commit-and-branch.rb

src/lab/git-dirty:
	./script/update-git-commit-and-branch.rb

public/lab/lab.grapher.js: \
	$(GRAPHER_SRC_FILES) \
	$(COMMON_SRC_FILES)
	$(R_OPTIMIZER) -o src/lab/grapher/grapher.build.js

public/lab/lab.import-export.js: \
	$(IMPORT_EXPORT_SRC_FILES) \
	$(COMMON_SRC_FILES)
	$(R_OPTIMIZER) -o src/lab/import-export/import-export.build.js

public/lab/lab.mml-converter.js: \
	$(MML_CONVERTER_SRC_FILES) \
	$(LAB_SRC_FILES) \
	$(COMMON_SRC_FILES)
	$(R_OPTIMIZER) -o src/lab/mml-converter/mml-converter.build.js

public/lab/jars:
	mkdir -p public/lab/jars

public/lab/jars/lab-sensor-applet-interface-dist: \
	vendor/lab-sensor-applet-interface-dist \
	public/lab/jars
	cp -R vendor/lab-sensor-applet-interface-dist/jars public/lab/jars/lab-sensor-applet-interface-dist

public/lab/resources:
	cp -R ./src/lab/resources ./public/lab/

# ------------------------------------------------
#
#   public/vendor
#
# External frameworks are built from git submodules checked out into vendor/.
# Just the generated libraries and licenses are copied to public/vendor
#
# ------------------------------------------------

public/vendor: \
	public/vendor/d3 \
	public/vendor/jquery/jquery.min.js \
	public/vendor/jquery-ui/jquery-ui.min.js \
	public/vendor/jquery-ui-touch-punch/jquery.ui.touch-punch.min.js \
	public/vendor/jquery-selectBoxIt/jquery.selectBoxIt.min.js \
	public/vendor/tinysort/jquery.tinysort.js \
	public/vendor/jquery-context-menu \
	public/vendor/modernizr \
	public/vendor/hijs \
	public/vendor/fonts \
	public/vendor/text \
	public/vendor/shutterbug/shutterbug.js \
	public/vendor/shutterbug/README.md \
	public/vendor/shutterbug/LICENSE.md \
	public/vendor/sensor-labquest-2-interface/sensor-labquest-2-interface.js \
	public/vendor/sensor-server-interface/sensor-server-interface.js \
	public/vendor/iframe-phone/iframe-phone.js \
	public/favicon.ico

public/vendor/d3: vendor/d3
	mkdir -p public/vendor/d3
	cp vendor/d3/d3*.js public/vendor/d3
	cp vendor/d3/LICENSE public/vendor/d3/LICENSE
	cp vendor/d3/README.md public/vendor/d3/README.md

public/vendor/jquery-ui-touch-punch/jquery.ui.touch-punch.min.js: \
	public/vendor/jquery-ui-touch-punch \
	vendor/jquery-ui-touch-punch/jquery.ui.touch-punch.min.js \
	vendor/jquery-ui-touch-punch/jquery.ui.touch-punch.js
	cp vendor/jquery-ui-touch-punch/jquery.ui.touch-punch.min.js public/vendor/jquery-ui-touch-punch
	cp vendor/jquery-ui-touch-punch/jquery.ui.touch-punch.js public/vendor/jquery-ui-touch-punch

public/vendor/jquery-ui-touch-punch:
	mkdir -p public/vendor/jquery-ui-touch-punch

public/vendor/jquery-selectBoxIt/jquery.selectBoxIt.min.js: \
	vendor/jquery-selectBoxIt/src/javascripts/jquery.selectBoxIt.js \
	vendor/jquery-selectBoxIt/src/javascripts/jquery.selectBoxIt.min.js \
	vendor/jquery-selectBoxIt/src/stylesheets/jquery.selectBoxIt.css \
	public/vendor/jquery-selectBoxIt
	cp vendor/jquery-selectBoxIt/src/javascripts/jquery.selectBoxIt.js public/vendor/jquery-selectBoxIt
	cp vendor/jquery-selectBoxIt/src/javascripts/jquery.selectBoxIt.min.js public/vendor/jquery-selectBoxIt
	cp vendor/jquery-selectBoxIt/src/stylesheets/jquery.selectBoxIt.css public/vendor/jquery-selectBoxIt

public/vendor/jquery-selectBoxIt:
	mkdir -p public/vendor/jquery-selectBoxIt

public/vendor/jquery-context-menu:
	mkdir -p public/vendor/jquery-context-menu
	cp vendor/jquery-context-menu/src/jquery.contextMenu.js public/vendor/jquery-context-menu
	cp vendor/jquery-context-menu/src/jquery.contextMenu.css public/vendor/jquery-context-menu

public/vendor/jquery/jquery.min.js: \
	vendor/jquery/dist/jquery.min.js \
	public/vendor/jquery
	cp vendor/jquery/dist/jquery*.js public/vendor/jquery
	cp vendor/jquery/dist/jquery.min.map public/vendor/jquery
	cp vendor/jquery/MIT-LICENSE.txt public/vendor/jquery
	cp vendor/jquery/README.md public/vendor/jquery

public/vendor/jquery:
	mkdir -p public/vendor/jquery

public/vendor/jquery-ui/jquery-ui.min.js: \
	vendor/jquery-ui/dist/jquery-ui.min.js \
	public/vendor/jquery-ui
	cp -r vendor/jquery-ui/dist/* public/vendor/jquery-ui
	cp -r vendor/jquery-ui/themes/base/images public/vendor/jquery-ui
	cp vendor/jquery-ui/MIT-LICENSE.txt public/vendor/jquery-ui

public/vendor/jquery-ui:
	mkdir -p public/vendor/jquery-ui

public/vendor/tinysort:
	mkdir -p public/vendor/tinysort

public/vendor/tinysort/jquery.tinysort.js: \
	public/vendor/tinysort
	cp -r vendor/tinysort/src/* public/vendor/tinysort
	cp vendor/tinysort/README.md public/vendor/tinysort

public/vendor/modernizr:
	mkdir -p public/vendor/modernizr
	cp vendor/modernizr/modernizr.js public/vendor/modernizr
	cp vendor/modernizr/readme.md public/vendor/modernizr

public/vendor/sizzle:
	mkdir -p public/vendor/sizzle
	cp vendor/sizzle/sizzle.js public/vendor/sizzle
	cp vendor/sizzle/LICENSE public/vendor/sizzle
	cp vendor/sizzle/README public/vendor/sizzle

public/vendor/hijs:
	mkdir -p public/vendor/hijs
	cp vendor/hijs/hijs.js public/vendor/hijs
	cp vendor/hijs/LICENSE public/vendor/hijs
	cp vendor/hijs/README.md public/vendor/hijs

public/vendor/fonts: $(FONT_FOLDERS)
	mkdir -p public/vendor/fonts
	cp -R vendor/fonts public/vendor/
	rm -rf public/vendor/fonts/Font-Awesome/.git*
	rm -f public/vendor/fonts/Font-Awesome/.gitignore
	rm -rf public/vendor/fonts/Font-Awesome/less
	rm -rf public/vendor/fonts/Font-Awesome/sass

public/vendor/text:
	mkdir -p public/vendor/text
	cp vendor/text/text.js public/vendor/text
	cp vendor/text/LICENSE public/vendor/text
	cp vendor/text/README.md public/vendor/text

public/vendor/shutterbug:
	mkdir -p public/vendor/shutterbug

public/vendor/shutterbug/shutterbug.js: public/vendor/shutterbug \
	vendor/shutterbug/shutterbug.js
	sed -e s'/CONVERT_PATH/shutterbug\/make_snapshot/' vendor/shutterbug/shutterbug.js > public/vendor/shutterbug/shutterbug.js

public/vendor/shutterbug/README.md: public/vendor/shutterbug \
	vendor/shutterbug/README.md
	cp vendor/shutterbug/README.md public/vendor/shutterbug

public/vendor/shutterbug/LICENSE.md: public/vendor/shutterbug \
	vendor/shutterbug/LICENSE.md
	cp vendor/shutterbug/LICENSE.md public/vendor/shutterbug

public/vendor/sensor-labquest-2-interface/sensor-labquest-2-interface.js: \
	public/vendor/sensor-labquest-2-interface \
	vendor/sensor-labquest-2-interface/dist/sensor-labquest-2-interface.js
	cp vendor/sensor-labquest-2-interface/dist/sensor-labquest-2-interface.js public/vendor/sensor-labquest-2-interface/

public/vendor/sensor-labquest-2-interface:
	mkdir -p public/vendor/sensor-labquest-2-interface

public/vendor/sensor-server-interface/sensor-server-interface.js: \
	public/vendor/sensor-server-interface \
	vendor/sensor-server-interface/dist/sensor-server-interface.js
	cp vendor/sensor-server-interface/dist/sensor-server-interface.js public/vendor/sensor-server-interface/

public/vendor/sensor-server-interface:
	mkdir -p public/vendor/sensor-server-interface

public/vendor/iframe-phone/iframe-phone.js: \
	public/vendor/iframe-phone \
	vendor/iframe-phone/dist/iframe-phone.js
	cp vendor/iframe-phone/dist/iframe-phone.js public/vendor/iframe-phone/

public/vendor/iframe-phone:
	mkdir -p public/vendor/iframe-phone

public/favicon.ico:
	cp -f src/favicon.ico public/favicon.ico

vendor/jquery/dist/jquery.min.js: vendor/jquery
	cd vendor/jquery; npm install; \
	 npm install grunt-cli; \
	 ./node_modules/grunt-cli/bin/grunt

vendor/jquery:
	git submodule update --init --recursive

vendor/jquery-ui/dist/jquery-ui.min.js: vendor/jquery-ui
	cd vendor/jquery-ui; npm install; \
	npm install grunt-cli; \
	./node_modules/grunt-cli/bin/grunt build

vendor/jquery-ui:
	git submodule update --init --recursive

vendor/lab-sensor-applet-interface-dist:
	git submodule update --init --recursive

vendor/sensor-labquest-2-interface/dist/sensor-labquest-2-interface.js:
	git submodule update --init --recursive

vendor/sensor-server-interface/dist/sensor-server-interface.js:
	git submodule update --init --recursive

vendor/shutterbug:
	mkdir -p vendor/shutterbug

vendor/shutterbug/shutterbug.js: vendor/shutterbug \
	$(SHUTTERBUG_GEM)/lib/shutterbug/handlers/shutterbug.js
	cp $(SHUTTERBUG_GEM)/lib/shutterbug/handlers/shutterbug.js vendor/shutterbug

vendor/shutterbug/README.md: vendor/shutterbug \
	$(SHUTTERBUG_GEM)/README.md
	cp $(SHUTTERBUG_GEM)/README.md vendor/shutterbug

vendor/shutterbug/LICENSE.md: vendor/shutterbug \
	$(SHUTTERBUG_GEM)/LICENSE.md
	cp $(SHUTTERBUG_GEM)/LICENSE.md vendor/shutterbug

# ------------------------------------------------
#
#   targets for generating html, js, and css resources
#
# ------------------------------------------------

test/%.html: test/%.html.haml
	haml $< $@

public/%.html: src/%.html.haml script/setup.rb
	haml -r ./script/setup.rb $< $@

public/%.html: src/%.html
	cp $< $@

public/%.css: src/%.css
	cp $< $@

public/grapher.css: src/grapher.sass \
	src/sass/lab/_colors.sass \
	src/sass/lab/_bar_graph.sass \
	src/sass/lab/_graphs.sass \
	public/lab-grapher.scss
	$(SASS_COMPILER) src/grapher.sass public/grapher.css

public/%.css: %.scss
	$(SASS_COMPILER) $< $@

public/lab-grapher.scss:
	cp vendor/lab-grapher/css/lab-grapher.css public/lab-grapher.scss

public/%.css: %.sass $(SASS_LAB_LIBRARY_FILES) \
	public/lab-grapher.scss
	@echo $($<)
	$(SASS_COMPILER) $< $@

# replace relative references to .md files for the static build
# look for pattern like ](*.md) replace with ](*.html)
# the ':' is hack so it doesn't match absolute http:// urls
# the second command is necessary to match anchor references in md files
%.md.static: %.md
	@rm -f $@
	sed -e s';\](\([^):]*\)\.md);\](\1.html);' -e s';\](\([^):]*\)\.md\(#[^)]*\));\](\1.html\2);' $< > $@

public/developer-doc/%.html: developer-doc/%.md.static
	@rm -f $@
	$(MARKDOWN_COMPILER) -i GFM $< --template src/layouts/developer-doc.html.erb > $@

public/%.html: %.md.static
	@rm -f $@
	$(MARKDOWN_COMPILER) $< --toc-levels 2..6 --template src/layouts/top-level.html.erb > $@

public/interactives/%.json: src/interactives/%.json
	@cp $< $@

public/models/%.json: src/models/%.json
	@cp $< $@

# delete the .md.static files and don't bother creating them if they don't need to be
.INTERMEDIATE: %.md.static

# ------------------------------------------------
#
#   Targets to help debugging/development of Makefile
#
# ------------------------------------------------

.PHONY: h
h:
	@echo $(HAML_FILES)

.PHONY: s
s:
	@echo $(SASS_FILES)

.PHONY: s1
sl:
	@echo $(SASS_LAB_LIBRARY_FILES)

.PHONY: m
m:
	@echo $(MARKDOWN_FILES)

.PHONY: cm
cm:
	@echo $(COMMON_SRC_FILES)

.PHONY: md2
md2:
	@echo $(MD2D_SRC_FILES)

.PHONY: gr
gr:
	@echo $(GRAPHER_SRC_FILES)

.PHONY: int
int:
	@echo $(INTERACTIVE_FILES)

.PHONY: sources
sources:
	@echo $(LAB_SRC_FILES)
