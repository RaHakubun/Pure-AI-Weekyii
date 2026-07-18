@ECHO OFF
SET APP_BASE_NAME=%~n0
SET APP_HOME=%~dp0
SET DEFAULT_JVM_OPTS=-Xmx64m -Xms64m
SET CLASSPATH=%APP_HOME%\gradle\wrapper\gradle-wrapper.jar

"%JAVA_HOME%\bin\java" %DEFAULT_JVM_OPTS% -cp "%CLASSPATH%" org.gradle.wrapper.GradleWrapperMain %*
