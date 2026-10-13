package com.ksh321.songrecord.api.account;
import java.util.UUID;
/** A successful return proves both owned final and temporary prefixes are empty. */
public interface DeletionObjects {void clearOwner(UUID owner,Runnable leaseFence)throws Exception;}
