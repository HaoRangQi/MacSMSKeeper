APP_NAME := 短信管家
BUILD    := build
BUNDLE   := $(BUILD)/$(APP_NAME).app
BIN      := $(BUNDLE)/Contents/MacOS/SMSKeeper

.PHONY: all build run clean selftest snapshot exporttest help

all: build

## 编译并组装 .app 到 build/
build:
	@./scripts/build.sh

## 编译后启动
run: build
	@open "$(BUNDLE)"

## 删除构建产物
clean:
	@rm -rf "$(BUILD)"

## 自检：载入、分类、搜索、导航、删除/还原闭环
selftest: build
	@SMSKEEPER_SELFTEST=1 "$(BIN)" 2>&1 | grep '\[test\]' || true

## 重新生成 docs/images 下的界面截图
snapshot: build
	@SMSKEEPER_SNAPSHOT="$(CURDIR)/docs/images" "$(BIN)" >/dev/null 2>&1 || true
	@echo "截图已更新：docs/images"

## 导出三种格式的样例到 docs/examples
exporttest: build
	@SMSKEEPER_EXPORTTEST="$(CURDIR)/docs/examples" "$(BIN)" >/dev/null 2>&1 || true
	@echo "样例已更新：docs/examples"

help:
	@echo "make build       编译"
	@echo "make run         编译并运行"
	@echo "make selftest    运行自检"
	@echo "make snapshot    更新界面截图"
	@echo "make clean       清理产物"
