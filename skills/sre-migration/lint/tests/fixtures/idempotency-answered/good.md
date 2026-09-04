### 各操作說明

* **precheck**
  是否提供：Yes
  說明：確認目標 company 存在，列印 name/region/shipToCode 供人工核對。
  可否重複執行：Yes

* **backup**
  是否提供：Yes
  說明：將該列寫入本機 JSON 檔，作為 rollback/restore 依據。
  可否重複執行：Yes

* **migrate**
  是否提供：Yes
  說明：以 INSERT ... ON DUPLICATE KEY UPDATE 對指定列做加總修正。
  可否重複執行：**No** — 寫入為加總，重複執行會套用兩次。

* **verify**
  是否提供：Yes
  說明：重新讀取該列並與備份檔比對，輸出 PASS/FAIL。
  可否重複執行：Yes

* **rollback**
  是否提供：Yes
  說明：依備份檔的 day_before 執行反向 UPDATE。
  可否重複執行：Yes

* **restore**
  是否提供：**No**，原因：本次僅為兩列數值修正，rollback 已足以精確還原。
