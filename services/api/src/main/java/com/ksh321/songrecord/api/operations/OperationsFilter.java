package com.ksh321.songrecord.api.operations;
import java.io.IOException;
import java.time.Instant;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import org.springframework.stereotype.Component;
import org.springframework.context.annotation.Profile;
import org.springframework.core.annotation.Order;
import org.springframework.core.Ordered;
@Component @Profile({"staging","prod"}) @Order(Ordered.HIGHEST_PRECEDENCE+5)
public final class OperationsFilter extends org.springframework.web.filter.OncePerRequestFilter {
 private final OperationsRecorder recorder;
 public OperationsFilter(OperationsRecorder recorder){this.recorder=recorder;}
 @Override protected boolean shouldNotFilter(HttpServletRequest request){return !request.getRequestURI().startsWith("/v1/");}
 @Override protected void doFilterInternal(HttpServletRequest request,HttpServletResponse response,FilterChain chain)throws ServletException,IOException{
  var trace=OperationsContext.begin();long start=System.nanoTime();boolean failed=false;
  try{chain.doFilter(request,response);}catch(ServletException|IOException|RuntimeException error){failed=true;throw error;}
  finally{
   int status=failed?500:response.getStatus();var action=trace.activity!=null?trace.activity:OperationsContext.route(request.getMethod(),request.getRequestURI());
   var result=trace.failure!=null?trace.failure:status>=200&&status<300?OperationsContext.Result.SUCCESS:OperationsContext.Result.FAILURE;
   try{recorder.record(trace.actor,trace.target!=null?trace.target:OperationsContext.targetFromPath(request.getRequestURI()),trace.actor==null?"ANONYMOUS":"USER",action,result,status,(System.nanoTime()-start)/1000000,Instant.now());}finally{OperationsContext.clear();}
  }
 }
}
