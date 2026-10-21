package me.zed_0xff.zombie_buddy.annotations;

import java.lang.annotation.*;

@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.TYPE)
public @interface Patch {
    String className();
    String methodName();
    boolean isAdvice() default true;
    boolean warmUp() default false;
    boolean strictMatch() default false;
    boolean debug() default false;

    @Retention(RetentionPolicy.RUNTIME) @Target(ElementType.METHOD)
    @interface OnEnter { boolean skipOn() default false; }

    @Retention(RetentionPolicy.RUNTIME) @Target(ElementType.METHOD)
    @interface OnExit { }

    @Retention(RetentionPolicy.RUNTIME) @Target(ElementType.PARAMETER)
    @interface Return { boolean readOnly() default true; }

    @Retention(RetentionPolicy.RUNTIME) @Target(ElementType.PARAMETER)
    @interface Argument { int value() default 0; boolean readOnly() default true; boolean optional() default false; }
}
