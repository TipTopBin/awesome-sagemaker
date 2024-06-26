import argparse
import logging
import os

import evaluate
import numpy as np
from datasets import load_from_disk
from transformers import (
    AutoModelForSeq2SeqLM,
    AutoTokenizer,
    DataCollatorForSeq2Seq,
    Seq2SeqTrainer,
    Seq2SeqTrainingArguments,
)

import argparse

def parse_hf_hub():
    parser = argparse.ArgumentParser()

    # Push to Hub Parameters
    parser.add_argument("--push_to_hub", type=bool, default=False)
    parser.add_argument("--hub_model_id", type=str, default=None)
    parser.add_argument("--hub_strategy", type=str, default=None)
    parser.add_argument("--hub_token", type=str, default=None)    
    parser.add_argument("--hub_push", type=bool, default=False)

    args, _ = parser.parse_known_args()

    # make sure we have required parameters to push
    if args.push_to_hub:
        if args.hub_strategy is None:
            raise ValueError("--hub_strategy is required when pushing to Hub")
        if args.hub_token is None:
            raise ValueError("--hub_token is required when pushing to Hub")

    # sets hub id if not provided
    if args.hub_model_id is None:
        args.hub_model_id = args.model_id.replace("/", "--")  

    return args

def push_to_hub(hub_args, trainer={}, model={}):
    if not (hub_args.push_to_hub or hub_args.hub_push):
      return

    # save best model, metrics and create model card
    if trainer:
      trainer.create_model_card(model_name=hub_args.hub_model_id)
      trainer.push_to_hub()
    elif model:
      model.push_to_hub(hub_args.hub_model_id)
    #   model.push_to_hub("xxx/xxxxx", use_auth_token=True)
    
    
rouge = evaluate.load("rouge")

def compute_metrics(eval_pred):
    predictions, labels = eval_pred
    decoded_preds = tokenizer.batch_decode(predictions, skip_special_tokens=True)
    labels = np.where(labels != -100, labels, tokenizer.pad_token_id)
    decoded_labels = tokenizer.batch_decode(labels, skip_special_tokens=True)
    result = rouge.compute(predictions=decoded_preds, references=decoded_labels, use_stemmer=True)
    result = {k: round(v * 100, 4) for k, v in result.items()}
    prediction_lens = [np.count_nonzero(pred != tokenizer.pad_token_id) for pred in predictions]
    result["gen_len"] = np.mean(prediction_lens)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()

    # hyperparameters are passed as command-line arguments to the script.
    parser.add_argument("--model-name", type=str)
    parser.add_argument("--learning-rate", type=str, default=5e-5)
    parser.add_argument("--epochs", type=int, default=3)
    parser.add_argument("--train-batch-size", type=int, default=2)
    parser.add_argument("--eval-batch-size", type=int, default=8)
    parser.add_argument("--evaluation-strategy", type=str, default="epoch")
    parser.add_argument("--save-strategy", type=str, default="epoch")
    parser.add_argument("--save-steps", type=int, default=500)
    parser.add_argument("--check-points-dir", type=str, default="/opt/ml/checkpoints")

    # Data, model, and output directories
    parser.add_argument("--output-data-dir", type=str, default=os.environ["SM_OUTPUT_DATA_DIR"])
    parser.add_argument("--model-dir", type=str, default=os.environ["SM_MODEL_DIR"])
    parser.add_argument("--train-dir", type=str, default=os.environ["SM_CHANNEL_TRAIN"])
    parser.add_argument("--valid-dir", type=str, default=os.environ["SM_CHANNEL_VALID"])
    args, _ = parser.parse_known_args()

    hub_args = parse_hf_hub()    
    
    # load datasets
    train_dataset = load_from_disk(args.train_dir)
    valid_dataset = load_from_disk(args.valid_dir)

    logger = logging.getLogger(__name__)
    logger.info(f"training set: {train_dataset}")
    logger.info(f"validation set: {valid_dataset}")

    # download model and tokenizer from model hub
    model = AutoModelForSeq2SeqLM.from_pretrained(args.model_name)
    tokenizer = AutoTokenizer.from_pretrained(args.model_name)

    data_collator = DataCollatorForSeq2Seq(tokenizer=tokenizer, model=model)

    # sequence to sequence training arguments
    training_args = Seq2SeqTrainingArguments(
        output_dir=args.check_points_dir,
        num_train_epochs=args.epochs,
        per_device_train_batch_size=args.train_batch_size,
        per_device_eval_batch_size=args.eval_batch_size,
        save_strategy=args.save_strategy,
        save_steps=args.save_steps,
        save_total_limit=3,
        evaluation_strategy=args.evaluation_strategy,
        logging_dir=f"{args.output_data_dir}/logs",
        learning_rate=float(args.learning_rate),
        predict_with_generate=True,
        load_best_model_at_end=True,
        weight_decay=0.01,
        fp16=False,
        # push to hub parameters
        push_to_hub=hub_args.push_to_hub,
        hub_strategy=hub_args.hub_strategy,
        hub_model_id=hub_args.hub_model_id,
        hub_token=hub_args.hub_token,        
    )

    # trainer object
    trainer = Seq2SeqTrainer(
        model=model,
        args=training_args,
        tokenizer=tokenizer,
        train_dataset=train_dataset,
        eval_dataset=valid_dataset,
        data_collator=data_collator,
        compute_metrics=compute_metrics,
    )

    # train model
    trainer.train()

    # Saves the model to s3
    logger.info("--- Save model to S3 ---")
    
    trainer.save_model(args.model_dir)
    tokenizer.save_pretrained(args.model_dir)
    
    logger.info("--- Save model to HF ---")    
    push_to_hub(hub_args, trainer=trainer)