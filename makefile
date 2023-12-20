APP = snake.sms
CC := wla-z80
RANDOM := $(shell od -A n -t d -N 1 /dev/urandom |tr -d ' ')
CFLAGS := -v -D SEED=$(RANDOM) -o
LD := wlalink
LDFLAGS := -v -d -s
MEKA_BIN := $(HOME)/Development/meka/meka/meka

SRC_DIR := ./src
BIN_DIR := ./bin
BUILD_DIR := ./build

all: clean config release run

release: $(APP)

$(APP): sms.lib main.o
	@echo "Linking $(APP):"
	$(LD) $(LDFLAGS) linkfile $(BIN_DIR)/$(APP)

sms.lib:
	@echo "Compiling library $@"
	$(CC) -l $(BUILD_DIR)/sms.lib $(SRC_DIR)/lib/sms.wla
	$(shell echo "\n[libraries]\nbank 0 slot 5 build/$@\n" >> linkfile)
	$(shell echo "\n[ramsections]\nbank 0 slot 5 \"SMS_Z80\"\n" >> linkfile)

main.o:
	@echo "Compiling object $@"
	$(CC) $(CFLAGS) $(BUILD_DIR)/$@ $(SRC_DIR)/main.asm
	$(shell echo "\n[objects]\nbuild/$@\n" >> linkfile)

run: $(APP)
	${MEKA_BIN} ${BIN_DIR}/${APP}

# config pre build
config:
	@echo create directories
	$(shell mkdir -p $(BIN_DIR) $(BUILD_DIR))
	@echo create linkfile
	$(shell > linkfile)

.PHONY: clean

clean:
	@echo "Cleaning:"
	$(RM) $(BUILD_DIR)/*
	$(RM) $(BIN_DIR)/*