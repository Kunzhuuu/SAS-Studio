options validvarname=upcase;
ods graphics on;

%let root = /home/u64503303;
libname out "&root/Kaplan-Meier";


/* 1. 准备 HDL 分组数据 */
data km_hdl_2011_2018;
    set out.nhanes_2011_2018_analysis;

    follow_year = follow_month / 12;

    length hdl_group $20;

    if hdl_abn = 0 then hdl_group = "HDL normal";
    else if hdl_abn = 1 then hdl_group = "HDL abnormal";
    else hdl_group = "Missing";

    if missing(follow_year) then delete;
    if missing(death) then delete;
    if hdl_group = "Missing" then delete;

    label
        follow_year = "Follow-up time in years"
        death       = "All-cause mortality"
        hdl_group   = "HDL cholesterol group";
run;


/* 2. 查看两组样本量和死亡人数 */
proc freq data=km_hdl_2011_2018;
    tables hdl_group * death / chisq norow nocol nopercent;
run;


/* 3. Kaplan-Meier 生存曲线 + Log-rank 检验 */
/* 修改点：删除了 notable，确保 ODS 可以捕获所需数据 */
proc lifetest data=km_hdl_2011_2018
    plots=survival(atrisk cb); 
    
    time follow_year * death(0);
    strata hdl_group / test=logrank;

    ods output
        ProductLimitEstimates = out.km_hdl_estimates
        HomTests              = out.km_hdl_logrank
        Quartiles             = out.km_hdl_quartiles
        CensoredSummary       = out.km_hdl_censored;
run;

ods graphics off;


/* 4. 输出 Log-rank 检验结果 */
title "Log-rank Test for HDL Normal vs Abnormal, NHANES 2011-2018";
proc print data=out.km_hdl_logrank label;
run;
title;


/* 5. 输出 KM 生存率估计 */
title "Kaplan-Meier Survival Estimates by HDL Group";
proc print data=out.km_hdl_estimates(obs=20) label; /* 建议加上 obs=20 避免打印过长 */
run;
title;


/* 6. 导出结果到 Excel */
proc export data=out.km_hdl_logrank
    outfile="&root/Kaplan-Meier/km_hdl_logrank.xlsx"
    dbms=xlsx
    replace;
run;

proc export data=out.km_hdl_estimates
    outfile="&root/Kaplan-Meier/km_hdl_estimates.xlsx"
    dbms=xlsx
    replace;
run;

proc export data=out.km_hdl_censored
    outfile="&root/Kaplan-Meier/km_hdl_censored.xlsx"
    dbms=xlsx
    replace;
run;