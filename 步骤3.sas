OPTIONS NOTES STIMER SOURCE SYNTAXCHECK; /* 建议开启日志以监控执行过程 */

/* 1. 定义基础根路径 */
%LET BASE_PATH = /home/u64503303;

/* 2. 定义高度参数化的合并宏（已修复命名空间映射） */
%MACRO IMPORT_CYCLE(YEAR_FOLDER, YEAR_PREFIX, YEAR_UNDERSCORE, SUFFIX);
    /* 参数说明：
       YEAR_FOLDER: 物理文件夹名 (带有连字符, 如 2011-2012)
       YEAR_PREFIX: XPT文件名前缀 (如 2011)
       YEAR_UNDERSCORE: DAT文件名中的年份格式 (带有下划线, 如 2011_2012)
       SUFFIX: NHANES 官方后缀 (如 G)
    */

    /* --- 导入基线特征 --- */
    /* 核心修正：物理路径包含 &YEAR_PREFIX (如 2011_)，
       但在 SET 语句中，读取 XPT 内部真正的表名时，必须去掉数字前缀，
       严格使用 NHANES 的原始内部表名 (如 DEMO_G) */

    LIBNAME x_demo XPORT "&BASE_PATH/&YEAR_FOLDER/&YEAR_PREFIX._DEMO_&SUFFIX..xpt";
    DATA d_&SUFFIX; SET x_demo.DEMO_&SUFFIX; 
        KEEP SEQN RIDAGEYR RIAGENDR; 
    RUN;

    LIBNAME x_hdl XPORT "&BASE_PATH/&YEAR_FOLDER/&YEAR_PREFIX._HDL_&SUFFIX..xpt";
    DATA h_&SUFFIX; SET x_hdl.HDL_&SUFFIX; 
        KEEP SEQN LBDHDD; 
    RUN;

    LIBNAME x_tchol XPORT "&BASE_PATH/&YEAR_FOLDER/&YEAR_PREFIX._TCHOL_&SUFFIX..xpt";
    DATA t_&SUFFIX; SET x_tchol.TCHOL_&SUFFIX; 
        KEEP SEQN LBDTCSI; 
    RUN;

    LIBNAME x_trig XPORT "&BASE_PATH/&YEAR_FOLDER/&YEAR_PREFIX._TRIGLY_&SUFFIX..xpt";
    DATA g_&SUFFIX; SET x_trig.TRIGLY_&SUFFIX; 
        KEEP SEQN LBXTR; 
    RUN;

    /* --- 读取生存结局数据 --- */
    /* 核心修正：使用 &YEAR_UNDERSCORE 确保精准匹配 2011_2012 格式 */
    DATA m_&SUFFIX;
        INFILE "&BASE_PATH/&YEAR_FOLDER/&YEAR_PREFIX._NHANES_&YEAR_UNDERSCORE._MORT_2019_PUBLIC.dat" LRECL=61 PAD MISSOVER;
        INPUT SEQN 1-6 MORTSTAT 16 PERMTH_INT 43-45;
    RUN;

    /* --- 排序与合并 --- */
    PROC SORT DATA=d_&SUFFIX; BY SEQN; RUN;
    PROC SORT DATA=h_&SUFFIX; BY SEQN; RUN;
    PROC SORT DATA=t_&SUFFIX; BY SEQN; RUN;
    PROC SORT DATA=g_&SUFFIX; BY SEQN; RUN;
    PROC SORT DATA=m_&SUFFIX; BY SEQN; RUN;

    DATA cycle_&SUFFIX;
        MERGE d_&SUFFIX(IN=a) h_&SUFFIX t_&SUFFIX g_&SUFFIX m_&SUFFIX;
        BY SEQN;
        IF a; /* 仅保留在人口学基线中存在的人员 */
        SURVEY_CYCLE = "&YEAR_FOLDER";
    RUN;
%MEND;

/* 3. 顺序执行四个周期的合并 (传入 4 个精确参数) */
%IMPORT_CYCLE(2011-2012, 2011, 2011_2012, G);
%IMPORT_CYCLE(2013-2014, 2013, 2013_2014, H);
%IMPORT_CYCLE(2015-2016, 2015, 2015_2016, I);
%IMPORT_CYCLE(2017-2018, 2017, 2017_2018, J);

/* 4. 纵向堆叠并执行多元 Cox 回归 */
DATA pooled_data;
    SET cycle_G cycle_H cycle_I cycle_J;
    /* 严谨性：剔除任何包含缺失值的样本，确保回归矩阵满秩 */
    IF NMISS(MORTSTAT, PERMTH_INT, LBDHDD, LBDTCSI, LBXTR, RIDAGEYR, RIAGENDR) = 0;
RUN;

/* 5. 构建多元 Cox 模型并进行 PH 假设检验 */
PROC PHREG DATA=pooled_data;
    CLASS RIAGENDR(REF='2') / PARAM=REF;
    MODEL PERMTH_INT * MORTSTAT(0) = LBDHDD LBDTCSI LBXTR RIDAGEYR RIAGENDR / RL;
    /* Schoenfeld 残差检验：SCI 顶刊的严谨性要求 */
    ASSESS PH / RESAMPLE;
    TITLE "2011-2018 NHANES 多因素生存风险评估 (Multivariate Cox)";
RUN;