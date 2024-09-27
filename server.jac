import:py from mtllm.llms {Ollama}
glob llm = Ollama(model_name='llama3.1');

# import:py from mtllm.llms {OpenAI}
# glob llm = OpenAI(model_name='gpt-4o');

import:jac from rag {RagEngine}
glob rag_engine:RagEngine = RagEngine();

enum ChatType {
    RAG : 'Need to use Retrievable information in specific documents to respond' = "RAG",
    QA : 'Given context is enough for an answer' = "user_qa",
    SMALLTALK : 'Handle casual conversations and small talk' = "smalltalk"
}

node Router {
    can 'route the query to the appropriate task type'
    classify(message:'query from the user to be routed.':str) -> ChatType by llm(method="Reason", temperature=0.0);
}

walker infer {
    has message:str;
    has chat_history: list[dict];

    can init_router with `root entry {
        visit [-->](`?Router) else {
            router_node = here ++> Router();
            router_node ++> RagChat();
            router_node ++> QAChat();
            router_node ++> SmallTalkChat();  # Adding SmallTalkChat to the router
            visit router_node;
        }
    }

    can route with Router entry {
        classification = here.classify(message = self.message);
        visit [-->](`?Chat)(?chat_type==classification);
    }
}

node Chat {
    has chat_type: ChatType;
}

node RagChat :Chat: {
    has chat_type: ChatType = ChatType.RAG;

    can respond with infer entry {
        can 'Respond to message using chat_history as context and agent_role as the goal of the agent'
        respond_with_llm(
            message:'current message':str,
            chat_history: 'chat history':list[dict],
            agent_role:'role of the agent responding':str,
            context:'retrieved context from documents':list
        ) -> 'response':str by llm();
        
        data = rag_engine.get_from_chroma(query=here.message);
        here.response = respond_with_llm(
            here.message, 
            here.chat_history, 
            "You are a conversation agent designed to help users with their queries based on the documents provided", 
            data
        );
    }
}

node QAChat :Chat: {
    has chat_type: ChatType = ChatType.QA;

    can respond with infer entry {
        can 'Respond to message using chat_history as context and agent_role as the goal of the agent'
        respond_with_llm(
            message:'current message':str,
            chat_history: 'chat history':list[dict],
            agent_role:'role of the agent responding':str
        ) -> 'response':str by llm();

        here.response = respond_with_llm(
            here.message, 
            here.chat_history, 
            agent_role="You are a conversation agent designed to help users with their queries"
        );
    }
}

# Custom SmallTalkChat node for handling small talk conversations
node SmallTalkChat :Chat: {
    has chat_type: ChatType = ChatType.SMALLTALK;

    can respond with infer entry {
        can 'Respond to small talk or casual conversation'
        respond_with_llm(
            message:'current message':str,
            chat_history: 'chat history':list[dict],
            agent_role:'role of the agent responding':str
        ) -> 'response':str by llm();

        here.response = respond_with_llm(
            here.message, 
            here.chat_history, 
            agent_role="You are a friendly assistant for small talk and casual conversation."
        );
    }
}

walker interact {
    has message: str;
    has session_id: str;

    can init_session with `root entry {
        visit [-->](`?Session)(?id == self.session_id) else {
            session_node = here ++> Session(id=self.session_id, chat_history=[], status=1);
            print("Session Node Created");
            visit session_node;
        }
    }
}

node Session {
    has id: str;
    has chat_history: list[dict];
    has status: int = 1;

    can chat with interact entry {
        self.chat_history.append({"role": "user", "content": here.message});
        response = infer(message=here.message, chat_history=self.chat_history) spawn root;
        self.chat_history.append({"role": "assistant", "content": response.response});

        report {
            "response": response.response
        };
    }
}


# walker reverse_name {
#     has name: str;

#     can return_message with `root entry {
#         reversed_name = "".join(reversed(self.name));

#         report {
#             "response": "Your name backwards is: " + reversed_name
#         };
#     }
# }

# walker check_even_odd {
#     has number: int;

#     can return_message with `root entry {
#         result = "even" if self.number % 2 == 0 else "odd";

#         report {
#             "response": "The number " + str(self.number) + " is " + result + "."
#         };
#     }
# }
